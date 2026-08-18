<?php

use App\Http\Controllers\Api\AiController;
use App\Http\Controllers\Api\BootstrapController;
use App\Http\Controllers\Api\CollectionController;
use App\Http\Controllers\Api\ProfileController;
use App\Http\Middleware\VerifyFirebaseToken;
use Illuminate\Support\Facades\Route;

/*
| Every route below is scoped to the account in the verified Firebase ID
| token — the uid never appears in a URL, so there is no path for a client to
| ask for someone else's data.
*/

Route::get('/health', fn () => response()->json([
    'status' => 'ok',
    'service' => 'spendsense-api',
]));

Route::middleware([VerifyFirebaseToken::class, 'throttle:120,1'])->prefix('v1')->group(function () {
    Route::post('/bootstrap', [BootstrapController::class, 'store']);

    Route::get('/profile', [ProfileController::class, 'show']);
    Route::put('/profile', [ProfileController::class, 'update']);

    // Far tighter than the rest: this one spends the owner's Gemini quota,
    // and anyone can mint an anonymous account, so an unlimited endpoint is
    // an open invitation to run up the bill. Twenty a minute is well above
    // what scanning receipts and chatting actually needs.
    Route::post('/ai/generate', [AiController::class, 'generate'])->middleware('throttle:20,1');

    // Generic per-collection CRUD. The client generates document ids, so
    // create and update are the same idempotent PUT.
    Route::get('/{collection}', [CollectionController::class, 'index']);
    Route::get('/{collection}/{id}', [CollectionController::class, 'show']);
    Route::put('/{collection}/{id}', [CollectionController::class, 'put']);
    Route::delete('/{collection}/{id}', [CollectionController::class, 'destroy']);
});
