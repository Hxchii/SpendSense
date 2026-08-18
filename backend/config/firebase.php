<?php

return [
    /*
    | The Firebase project the app authenticates against. Used both to build
    | Firestore REST URLs and to check the "aud"/"iss" claims on incoming ID
    | tokens, so it must match the project the Flutter app signs in to.
    */
    'project_id' => env('FIREBASE_PROJECT_ID', ''),

    /*
    | Absolute path to the service account JSON downloaded from
    | Firebase Console -> Project settings -> Service accounts.
    | Grants this server write access to Firestore, so it is gitignored.
    */
    // A blank entry in .env would otherwise win over the default, so fall
    // back on empty rather than only on unset.
    'credentials' => env('FIREBASE_CREDENTIALS') ?: storage_path('app/firebase/service-account.json'),

    /*
    | The same service account passed inline instead of as a file, for hosts
    | where uploading one isn't an option. Raw JSON or base64-encoded JSON.
    | Takes precedence over the file path above when set.
    */
    'credentials_json' => env('FIREBASE_CREDENTIALS_JSON', ''),

    /*
    | Gemini is called from here rather than the app so the key never ships
    | inside an APK, where anyone can extract it.
    */
    'gemini_api_key' => env('GEMINI_API_KEY', ''),
    'gemini_model' => env('GEMINI_MODEL', 'gemini-3.1-flash-lite'),
];
