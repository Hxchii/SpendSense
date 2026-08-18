<?php

namespace App\Http\Controllers\Api;

use App\Http\Controllers\Controller;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\Http;
use Illuminate\Support\Facades\Log;
use Throwable;

/**
 * Proxies Gemini calls.
 *
 * The app used to hold the API key and call Google directly, which meant the
 * key shipped inside every APK — anyone can unzip one and read it. Routing
 * through here keeps the key on the server, and gives one place to add rate
 * limiting or swap models later without shipping a new build.
 *
 * The request body is passed through unchanged: the prompt and tool schemas
 * live in the Flutter repositories that own them, so this stays a transport
 * concern and doesn't need updating every time a prompt is tuned.
 */
class AiController extends Controller
{
    private const ENDPOINT = 'https://generativelanguage.googleapis.com/v1beta/models';

    public function generate(Request $request): JsonResponse
    {
        $apiKey = (string) config('firebase.gemini_api_key');
        if ($apiKey === '') {
            return response()->json(['message' => 'The AI service is not configured on the server.'], 503);
        }

        $payload = $request->json()->all();
        if (! is_array($payload) || ! isset($payload['contents'])) {
            return response()->json(['message' => 'Expected a Gemini request body with "contents".'], 422);
        }

        $model = (string) config('firebase.gemini_model');

        try {
            $response = Http::acceptJson()
                // Receipt images make these slow; well above the default.
                ->timeout(90)
                ->withHeaders(['x-goog-api-key' => $apiKey])
                ->post(self::ENDPOINT."/{$model}:generateContent", $payload);
        } catch (Throwable $e) {
            Log::error('Gemini request failed', ['exception' => $e->getMessage()]);

            return response()->json(['message' => 'Could not reach the AI service.'], 504);
        }

        if ($response->failed()) {
            // Log the detail, return a generic message: upstream errors can
            // echo back parts of the request, and the key lives in a header.
            Log::warning('Gemini returned an error', [
                'status' => $response->status(),
                'body' => $response->body(),
            ]);

            return response()->json(
                ['message' => 'The AI service could not complete that request.'],
                $response->status() === 429 ? 429 : 502
            );
        }

        return response()->json($response->json());
    }
}
