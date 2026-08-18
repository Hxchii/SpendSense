<?php

namespace App\Http\Controllers\Api;

use App\Http\Controllers\Controller;
use App\Services\FirestoreClient;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;

/**
 * CRUD for every per-account collection.
 *
 * The Flutter client stores each domain through one generic
 * FirestoreCollection<T>, with the shape of a document known only to that
 * feature's repository. Mirroring that here — one generic endpoint rather
 * than nine near-identical controllers — keeps the two sides in step: adding
 * a field to an entity needs no backend change at all.
 *
 * Documents are therefore passed through as-is. What is NOT passed through is
 * the account: the uid comes from the verified token, so a client cannot read
 * or write another account's data by changing a path.
 */
class CollectionController extends Controller
{
    /** Anything not on this list is rejected, so a client can't invent collections. */
    private const COLLECTIONS = [
        'wallets',
        'transactions',
        'categories',
        'budgets',
        'savings_goals',
        'recurring_bills',
        'receipts',
        'reminders',
        'ai_chat',
    ];

    public function __construct(private readonly FirestoreClient $firestore) {}

    public function index(Request $request, string $collection): JsonResponse
    {
        if (! $this->allowed($collection)) {
            return $this->unknownCollection($collection);
        }

        return response()->json([
            'data' => $this->firestore->list($this->uid($request), $collection),
        ]);
    }

    public function show(Request $request, string $collection, string $id): JsonResponse
    {
        if (! $this->allowed($collection)) {
            return $this->unknownCollection($collection);
        }

        $document = $this->firestore->get($this->uid($request), $collection, $id);
        if ($document === null) {
            return response()->json(['message' => 'Not found.'], 404);
        }

        return response()->json(['data' => $document]);
    }

    /**
     * Create or replace. The client generates the id (a UUID) before it ever
     * calls, so there is no separate create verb — PUT is idempotent, which
     * also makes a retry after a dropped connection safe.
     */
    public function put(Request $request, string $collection, string $id): JsonResponse
    {
        if (! $this->allowed($collection)) {
            return $this->unknownCollection($collection);
        }

        $payload = $request->json()->all();
        if (! is_array($payload)) {
            return response()->json(['message' => 'Expected a JSON object body.'], 422);
        }

        return response()->json([
            'data' => $this->firestore->put($this->uid($request), $collection, $id, $payload),
        ]);
    }

    public function destroy(Request $request, string $collection, string $id): JsonResponse
    {
        if (! $this->allowed($collection)) {
            return $this->unknownCollection($collection);
        }

        $this->firestore->delete($this->uid($request), $collection, $id);

        return response()->json(null, 204);
    }

    private function allowed(string $collection): bool
    {
        return in_array($collection, self::COLLECTIONS, true);
    }

    private function unknownCollection(string $collection): JsonResponse
    {
        return response()->json(['message' => "Unknown collection [{$collection}]."], 404);
    }

    private function uid(Request $request): string
    {
        return (string) $request->attributes->get('firebase_uid');
    }
}
