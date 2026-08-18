<?php

namespace App\Http\Controllers\Api;

use App\Http\Controllers\Controller;
use App\Services\FirestoreClient;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;

/**
 * The user profile is a single document (users/{uid}) rather than a row in a
 * subcollection, so it gets its own endpoint instead of going through
 * CollectionController.
 */
class ProfileController extends Controller
{
    public function __construct(private readonly FirestoreClient $firestore) {}

    public function show(Request $request): JsonResponse
    {
        $document = $this->firestore->getUserDocument($this->uid($request));

        // A brand-new account has no profile document yet. Returning an empty
        // object rather than a 404 lets the client apply its own defaults
        // without treating first launch as an error.
        return response()->json(['data' => $document ?? []]);
    }

    public function update(Request $request): JsonResponse
    {
        $payload = $request->json()->all();
        if (! is_array($payload)) {
            return response()->json(['message' => 'Expected a JSON object body.'], 422);
        }

        return response()->json([
            'data' => $this->firestore->putUserDocument($this->uid($request), $payload),
        ]);
    }

    private function uid(Request $request): string
    {
        return (string) $request->attributes->get('firebase_uid');
    }
}
