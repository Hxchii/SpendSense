<?php

namespace App\Http\Middleware;

use Closure;
use Firebase\JWT\JWT;
use Firebase\JWT\Key;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\Cache;
use Illuminate\Support\Facades\Http;
use Illuminate\Support\Facades\Log;
use Symfony\Component\HttpFoundation\Response;
use Throwable;

/**
 * Authenticates a request using the Firebase ID token the app sends as
 * `Authorization: Bearer <token>`, and puts the verified uid on the request.
 *
 * Verification is done locally against Google's published signing
 * certificates rather than by calling Firebase, so it costs one cached HTTP
 * request per day instead of one per API call. The uid is taken from the
 * token's signature-checked claims and never from anything the client can
 * set directly, which is what stops one account reading another's data.
 */
class VerifyFirebaseToken
{
    private const CERT_URL = 'https://www.googleapis.com/robot/v1/metadata/x509/securetoken@system.gserviceaccount.com';

    public function handle(Request $request, Closure $next): Response
    {
        $token = $this->bearerToken($request);
        if ($token === null) {
            return response()->json(['message' => 'Missing bearer token.'], 401);
        }

        $projectId = (string) config('firebase.project_id');

        // Fetched outside the decode try/catch: a failure to load Google's
        // certificates is a server problem, and reporting it as a bad token
        // sends the client off chasing its own credentials instead.
        try {
            $keys = $this->keys();
        } catch (Throwable $e) {
            Log::error('Could not load Firebase signing certificates', ['exception' => $e->getMessage()]);

            return response()->json(['message' => 'Could not verify credentials right now.'], 503);
        }

        try {
            $claims = JWT::decode($token, $keys);
        } catch (Throwable $e) {
            Log::debug('Rejected an ID token', ['reason' => $e->getMessage()]);

            return response()->json(['message' => 'Invalid or expired token.'], 401);
        }

        // A valid signature alone isn't enough: without these checks a token
        // minted for a different Firebase project would be accepted here.
        if (($claims->aud ?? null) !== $projectId) {
            return response()->json(['message' => 'Token was issued for a different project.'], 401);
        }
        if (($claims->iss ?? null) !== "https://securetoken.google.com/{$projectId}") {
            return response()->json(['message' => 'Unexpected token issuer.'], 401);
        }
        $uid = $claims->sub ?? null;
        if (! is_string($uid) || $uid === '') {
            return response()->json(['message' => 'Token has no subject.'], 401);
        }

        $request->attributes->set('firebase_uid', $uid);

        return $next($request);
    }

    private function bearerToken(Request $request): ?string
    {
        $header = $request->header('Authorization', '');

        return preg_match('/^Bearer\s+(.+)$/i', $header, $m) ? trim($m[1]) : null;
    }

    /**
     * Google rotates these certificates; caching for a day matches the
     * max-age they serve and keeps verification fast.
     *
     * @return array<string, Key>
     */
    private function keys(): array
    {
        $certificates = Cache::remember('firebase_signing_certs', now()->addDay(), function () {
            return Http::acceptJson()->timeout(10)->get(self::CERT_URL)->throw()->json();
        });

        $keys = [];
        foreach ($certificates as $kid => $certificate) {
            $keys[$kid] = new Key(openssl_pkey_get_public($certificate), 'RS256');
        }

        return $keys;
    }
}
