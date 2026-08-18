<?php

namespace App\Services;

use Google\Auth\CredentialsLoader;
use Google\Auth\HttpHandler\HttpHandlerFactory;
use Illuminate\Support\Facades\Http;
use RuntimeException;

/**
 * Minimal Firestore client built on the REST API.
 *
 * The official google/cloud-firestore library talks gRPC, which needs a
 * compiled PHP extension that is painful to install on Windows. Firestore
 * exposes the same operations over plain HTTPS, so this wraps those with an
 * OAuth token from the service account and keeps the dependency list to pure
 * PHP packages.
 *
 * Documents are read and written as ordinary PHP arrays; the Firestore
 * "typed value" wire format is translated in encode()/decode() so the rest of
 * the app never sees it.
 */
class FirestoreClient
{
    private string $projectId;
    private ?string $token = null;
    private int $tokenExpiresAt = 0;

    public function __construct()
    {
        $this->projectId = (string) config('firebase.project_id');
        if ($this->projectId === '') {
            throw new RuntimeException('FIREBASE_PROJECT_ID is not set.');
        }
    }

    private function baseUrl(): string
    {
        return "https://firestore.googleapis.com/v1/projects/{$this->projectId}/databases/(default)/documents";
    }

    /**
     * Service-account access token, cached until shortly before it expires so
     * every request doesn't pay for a token exchange.
     */
    private function token(): string
    {
        if ($this->token !== null && time() < $this->tokenExpiresAt - 60) {
            return $this->token;
        }

        $credentials = CredentialsLoader::makeCredentials(
            'https://www.googleapis.com/auth/datastore',
            $this->serviceAccount()
        );

        $authToken = $credentials->fetchAuthToken(HttpHandlerFactory::build());
        if (! isset($authToken['access_token'])) {
            throw new RuntimeException('Could not obtain a Google access token from the service account.');
        }

        $this->token = $authToken['access_token'];
        $this->tokenExpiresAt = time() + (int) ($authToken['expires_in'] ?? 3600);

        return $this->token;
    }

    /**
     * The service account, from an environment variable if one is set and
     * otherwise from a file on disk.
     *
     * Hosted environments generally have no way to commit or upload a file,
     * so the whole JSON is passed as a variable there — base64 accepted
     * because a raw private key spans multiple lines, which many dashboards
     * mangle. Locally the file path stays the more convenient option.
     *
     * @return array<string, mixed>
     */
    private function serviceAccount(): array
    {
        $inline = trim((string) config('firebase.credentials_json'));
        if ($inline !== '') {
            $decoded = json_decode($inline, true);
            if (! is_array($decoded)) {
                $fromBase64 = base64_decode($inline, true);
                $decoded = $fromBase64 === false ? null : json_decode($fromBase64, true);
            }
            if (! is_array($decoded)) {
                throw new RuntimeException('FIREBASE_CREDENTIALS_JSON is set but is not valid JSON or base64-encoded JSON.');
            }

            return $decoded;
        }

        $path = (string) config('firebase.credentials');
        if (! is_file($path)) {
            throw new RuntimeException(
                "No Firebase service account found. Set FIREBASE_CREDENTIALS_JSON, or place the file at {$path}. See backend/README.md."
            );
        }

        $decoded = json_decode((string) file_get_contents($path), true);
        if (! is_array($decoded)) {
            throw new RuntimeException("Service account at {$path} is not valid JSON.");
        }

        return $decoded;
    }

    private function request()
    {
        return Http::withToken($this->token())->acceptJson()->timeout(20);
    }

    /** Every document lives under users/{uid}, matching the security rules. */
    private function path(string $uid, string $collection, ?string $id = null): string
    {
        $suffix = $id === null ? '' : '/'.rawurlencode($id);

        return $this->baseUrl().'/users/'.rawurlencode($uid).'/'.rawurlencode($collection).$suffix;
    }

    /** @return array<int, array<string, mixed>> each row including its 'id' */
    public function list(string $uid, string $collection): array
    {
        $documents = [];
        $pageToken = null;

        // Firestore pages at 300 documents by default; follow the cursor so a
        // long transaction history doesn't come back silently truncated.
        do {
            $query = ['pageSize' => 300];
            if ($pageToken !== null) {
                $query['pageToken'] = $pageToken;
            }

            $response = $this->request()->get($this->path($uid, $collection), $query);
            if ($response->status() === 404) {
                return [];
            }
            $response->throw();

            foreach ($response->json('documents', []) as $document) {
                $documents[] = $this->decodeDocument($document);
            }
            $pageToken = $response->json('nextPageToken');
        } while ($pageToken);

        return $documents;
    }

    /** @return array<string, mixed>|null */
    public function get(string $uid, string $collection, string $id): ?array
    {
        $response = $this->request()->get($this->path($uid, $collection, $id));
        if ($response->status() === 404) {
            return null;
        }
        $response->throw();

        return $this->decodeDocument($response->json());
    }

    /**
     * Create or fully replace a document. Full replacement (not merge) is
     * deliberate: the app treats "field is null" as real state for its undo
     * and auto-contribute flows, so a cleared field has to actually clear.
     *
     * @param  array<string, mixed>  $data
     * @return array<string, mixed>
     */
    public function put(string $uid, string $collection, string $id, array $data): array
    {
        $response = $this->request()
            ->patch($this->path($uid, $collection, $id), ['fields' => $this->encodeFields($data)])
            ->throw();

        return $this->decodeDocument($response->json());
    }

    public function delete(string $uid, string $collection, string $id): void
    {
        $this->request()->delete($this->path($uid, $collection, $id))->throw();
    }

    /** The profile is a field set on users/{uid} itself, not a subcollection. */
    public function getUserDocument(string $uid): ?array
    {
        $response = $this->request()->get($this->baseUrl().'/users/'.rawurlencode($uid));
        if ($response->status() === 404) {
            return null;
        }
        $response->throw();

        return $this->decodeDocument($response->json());
    }

    /** @param array<string, mixed> $data */
    public function putUserDocument(string $uid, array $data): array
    {
        $response = $this->request()
            ->patch($this->baseUrl().'/users/'.rawurlencode($uid), ['fields' => $this->encodeFields($data)])
            ->throw();

        return $this->decodeDocument($response->json());
    }

    // --- wire format translation -------------------------------------------

    /** @param array<string, mixed> $document */
    private function decodeDocument(array $document): array
    {
        $segments = explode('/', $document['name'] ?? '');
        $decoded = $this->decodeFields($document['fields'] ?? []);
        $decoded['id'] = end($segments) ?: '';

        return $decoded;
    }

    /**
     * @param  array<string, mixed>  $fields
     * @return array<string, mixed>
     */
    private function decodeFields(array $fields): array
    {
        $out = [];
        foreach ($fields as $key => $value) {
            $out[$key] = $this->decodeValue($value);
        }

        return $out;
    }

    private function decodeValue(mixed $value): mixed
    {
        if (! is_array($value)) {
            return null;
        }

        return match (array_key_first($value)) {
            'nullValue' => null,
            'booleanValue' => (bool) $value['booleanValue'],
            // Firestore returns 64-bit ints as strings to survive JSON.
            'integerValue' => (int) $value['integerValue'],
            'doubleValue' => (float) $value['doubleValue'],
            'timestampValue' => $value['timestampValue'],
            'stringValue' => (string) $value['stringValue'],
            'arrayValue' => array_map(
                fn ($item) => $this->decodeValue($item),
                $value['arrayValue']['values'] ?? []
            ),
            'mapValue' => $this->decodeFields($value['mapValue']['fields'] ?? []),
            default => null,
        };
    }

    /**
     * @param  array<string, mixed>  $data
     * @return array<string, mixed>
     */
    private function encodeFields(array $data): array
    {
        $fields = [];
        foreach ($data as $key => $value) {
            if ($key === 'id') {
                continue;
            }
            $fields[$key] = $this->encodeValue($value);
        }

        return $fields;
    }

    private function encodeValue(mixed $value): array
    {
        if ($value === null) {
            return ['nullValue' => null];
        }
        if (is_bool($value)) {
            return ['booleanValue' => $value];
        }
        if (is_int($value)) {
            return ['integerValue' => (string) $value];
        }
        if (is_float($value)) {
            return ['doubleValue' => $value];
        }
        if (is_string($value)) {
            // ISO-8601 strings round-trip as real timestamps so date range
            // comparisons still work if anything ever queries them.
            return $this->looksLikeTimestamp($value)
                ? ['timestampValue' => $value]
                : ['stringValue' => $value];
        }
        if (is_array($value)) {
            return array_is_list($value)
                ? ['arrayValue' => ['values' => array_map(fn ($item) => $this->encodeValue($item), $value)]]
                : ['mapValue' => ['fields' => $this->encodeFields($value)]];
        }

        return ['stringValue' => (string) $value];
    }

    private function looksLikeTimestamp(string $value): bool
    {
        return (bool) preg_match('/^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(\.\d+)?(Z|[+-]\d{2}:\d{2})$/', $value);
    }
}
