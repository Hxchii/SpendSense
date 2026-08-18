<?php

namespace App\Console\Commands;

use Firebase\JWT\JWT;
use Firebase\JWT\Key;
use Illuminate\Console\Command;
use Illuminate\Support\Facades\Http;
use Throwable;

/** Prints why a specific ID token fails verification, instead of the generic 401. */
class VerifyTokenDebug extends Command
{
    protected $signature = 'firebase:verify-token {token}';

    protected $description = 'Decode a Firebase ID token and report exactly why it is accepted or rejected';

    public function handle(): int
    {
        $token = (string) $this->argument('token');
        $projectId = (string) config('firebase.project_id');
        $this->line("Configured project: [{$projectId}]");

        $parts = explode('.', $token);
        if (count($parts) !== 3) {
            $this->error('Not a JWT (expected 3 dot-separated parts).');

            return self::FAILURE;
        }
        $header = json_decode(base64_decode(strtr($parts[0], '-_', '+/')), true);
        $payload = json_decode(base64_decode(strtr($parts[1], '-_', '+/')), true);
        $this->line('Header: '.json_encode($header));
        $this->line('aud: '.($payload['aud'] ?? '(none)'));
        $this->line('iss: '.($payload['iss'] ?? '(none)'));
        $this->line('sub: '.($payload['sub'] ?? '(none)'));
        $this->line('exp: '.($payload['exp'] ?? '(none)').' (now '.time().')');

        try {
            $certs = Http::acceptJson()->timeout(10)
                ->get('https://www.googleapis.com/robot/v1/metadata/x509/securetoken@system.gserviceaccount.com')
                ->throw()->json();
        } catch (Throwable $e) {
            $this->error('Could not fetch Google signing certificates: '.$e->getMessage());

            return self::FAILURE;
        }
        $this->line('Fetched '.count($certs).' signing certificates. kids: '.implode(', ', array_keys($certs)));

        if (! isset($certs[$header['kid'] ?? ''])) {
            $this->error("Token's kid [{$header['kid']}] is not among Google's current certificates.");

            return self::FAILURE;
        }

        $keys = [];
        foreach ($certs as $kid => $certificate) {
            $public = openssl_pkey_get_public($certificate);
            if ($public === false) {
                $this->error("openssl_pkey_get_public failed for kid {$kid}: ".openssl_error_string());

                return self::FAILURE;
            }
            $keys[$kid] = new Key($public, 'RS256');
        }

        try {
            JWT::decode($token, $keys);
            $this->info('Signature verified successfully.');
        } catch (Throwable $e) {
            $this->error('JWT::decode threw '.$e::class.': '.$e->getMessage());

            return self::FAILURE;
        }

        return self::SUCCESS;
    }
}
