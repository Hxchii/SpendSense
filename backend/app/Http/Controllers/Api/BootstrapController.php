<?php

namespace App\Http\Controllers\Api;

use App\Http\Controllers\Controller;
use App\Services\FirestoreClient;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;

/**
 * Gives a new account the standard category set, so a user can record a
 * transaction or scan a receipt immediately instead of having to build a
 * taxonomy first.
 *
 * Enforced here rather than in the app so the rule holds for every client,
 * and so an account created before a new default existed picks it up on its
 * next launch.
 */
class BootstrapController extends Controller
{
    /**
     * Ids are fixed rather than generated: re-running must overwrite the same
     * documents instead of creating a second set, and the receipt scanner
     * resolves 'cat-other' by id when nothing else matches.
     */
    private const DEFAULT_CATEGORIES = [
        ['id' => 'cat-salary', 'name' => 'Salary', 'type' => 'income', 'iconKey' => 'salary', 'colorHex' => '#2a78d6'],
        ['id' => 'cat-allowance', 'name' => 'Allowance', 'type' => 'income', 'iconKey' => 'allowance', 'colorHex' => '#008300'],
        ['id' => 'cat-food', 'name' => 'Food', 'type' => 'expense', 'iconKey' => 'food', 'colorHex' => '#2a78d6'],
        ['id' => 'cat-transport', 'name' => 'Transport', 'type' => 'expense', 'iconKey' => 'transport', 'colorHex' => '#eb6834'],
        ['id' => 'cat-bills', 'name' => 'Bills & Utilities', 'type' => 'expense', 'iconKey' => 'bills', 'colorHex' => '#1baf7a'],
        ['id' => 'cat-shopping', 'name' => 'Shopping', 'type' => 'expense', 'iconKey' => 'shopping', 'colorHex' => '#eda100'],
        ['id' => 'cat-entertainment', 'name' => 'Entertainment', 'type' => 'expense', 'iconKey' => 'entertainment', 'colorHex' => '#e87ba4'],
        ['id' => 'cat-health', 'name' => 'Health', 'type' => 'expense', 'iconKey' => 'health', 'colorHex' => '#008300'],
        ['id' => 'cat-education', 'name' => 'Education', 'type' => 'expense', 'iconKey' => 'education', 'colorHex' => '#4a3aa7'],
        // Money moved into a savings goal leaves a wallet but isn't spending;
        // keeping it out of "Other" stops contributions eating that budget.
        ['id' => 'cat-savings', 'name' => 'Savings', 'type' => 'expense', 'iconKey' => 'piggyBank', 'colorHex' => '#1baf7a'],
        ['id' => 'cat-other', 'name' => 'Other', 'type' => 'expense', 'iconKey' => 'other', 'colorHex' => '#e34948'],
    ];

    public function __construct(private readonly FirestoreClient $firestore) {}

    public function store(Request $request): JsonResponse
    {
        $uid = (string) $request->attributes->get('firebase_uid');

        // Only genuinely absent categories are written. Archiving sets a flag
        // rather than deleting, so an archived category still counts as
        // present and is never resurrected, and a renamed or recoloured
        // default is left exactly as the user left it.
        $existing = collect($this->firestore->list($uid, 'categories'))
            ->pluck('id')
            ->all();

        $created = [];
        foreach (self::DEFAULT_CATEGORIES as $category) {
            if (in_array($category['id'], $existing, true)) {
                continue;
            }
            $this->firestore->put($uid, 'categories', $category['id'], [
                'name' => $category['name'],
                'type' => $category['type'],
                'iconKey' => $category['iconKey'],
                'colorHex' => $category['colorHex'],
                'isDefault' => true,
                'archived' => false,
            ]);
            $created[] = $category['id'];
        }

        return response()->json(['data' => ['created' => $created]]);
    }
}
