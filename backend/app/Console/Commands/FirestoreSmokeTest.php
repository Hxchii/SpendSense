<?php

namespace App\Console\Commands;

use App\Services\FirestoreClient;
use Illuminate\Console\Command;
use Throwable;

/**
 * Round-trips a throwaway document so the service-account credentials and the
 * REST wire-format translation can be verified without needing a signed-in
 * client to produce an ID token first.
 */
class FirestoreSmokeTest extends Command
{
    protected $signature = 'firestore:smoke {--uid=smoke-test-uid}';

    protected $description = 'Verify Firestore credentials by writing, reading and deleting a temporary document';

    public function handle(FirestoreClient $firestore): int
    {
        $uid = (string) $this->option('uid');
        $id = 'smoke-'.bin2hex(random_bytes(4));

        // Deliberately mixed types: ints must survive as ints (money is stored
        // in minor units), nulls must stay null, and nested maps/lists are
        // what receipt line items use.
        $payload = [
            'name' => 'Smoke Test Wallet',
            'type' => 'cash',
            'startingBalanceMinor' => 150050,
            'archived' => false,
            'clearedField' => null,
            'createdAt' => now()->toIso8601ZuluString('microsecond'),
            'items' => [
                ['name' => 'Coffee', 'qty' => 2, 'priceMinor' => 9500],
            ],
        ];

        try {
            $this->line('Writing…');
            $firestore->put($uid, 'wallets', $id, $payload);

            $this->line('Reading back…');
            $read = $firestore->get($uid, 'wallets', $id);
            if ($read === null) {
                $this->error('Document was written but could not be read back.');

                return self::FAILURE;
            }

            foreach (['name', 'type', 'startingBalanceMinor', 'archived', 'items'] as $key) {
                $expected = $payload[$key];
                $actual = $read[$key] ?? null;
                // Loose comparison on purpose: Firestore does not preserve key
                // order inside a map, and == compares associative arrays by
                // key/value rather than by order. Types are asserted below.
                if ($expected != $actual) {
                    $this->error("Mismatch on [{$key}]: expected ".json_encode($expected).', got '.json_encode($actual));

                    return self::FAILURE;
                }
            }
            if (! array_key_exists('clearedField', $read) || $read['clearedField'] !== null) {
                $this->error('A null field did not round-trip as null.');

                return self::FAILURE;
            }
            if (! is_int($read['startingBalanceMinor'])) {
                $this->error('Money did not round-trip as an integer.');

                return self::FAILURE;
            }
            if (! is_int($read['items'][0]['priceMinor'] ?? null)) {
                $this->error('Money nested inside a list did not round-trip as an integer.');

                return self::FAILURE;
            }
            if (! is_bool($read['archived'])) {
                $this->error('A boolean did not round-trip as a boolean.');

                return self::FAILURE;
            }

            $this->line('Listing…');
            $all = $firestore->list($uid, 'wallets');
            if (! collect($all)->contains(fn ($w) => ($w['id'] ?? null) === $id)) {
                $this->error('Document was not present in the collection listing.');

                return self::FAILURE;
            }

            $this->line('Deleting…');
            $firestore->delete($uid, 'wallets', $id);
            if ($firestore->get($uid, 'wallets', $id) !== null) {
                $this->error('Document still readable after delete.');

                return self::FAILURE;
            }
        } catch (Throwable $e) {
            $this->error('Firestore call failed: '.$e->getMessage());

            return self::FAILURE;
        }

        $this->info('Firestore round-trip OK — credentials, types and nesting all verified.');

        return self::SUCCESS;
    }
}
