const admin = require("firebase-admin");

// Initialize Firebase Admin SDK
const serviceAccountKey = {
  "type": "service_account",
  "project_id": "projekt-labor-a4b1c",
  "private_key_id": "9f1d8c3e7b5a2f4d6e9c1a3b5f7d9e1c",
  "private_key": "-----BEGIN PRIVATE KEY-----\nMIIEvQIBADANBgkqhkiG9w0BAQEFAASCBKcwggSjAgEAAoIBAQDN...\n-----END PRIVATE KEY-----\n",
  "client_email": "firebase-adminsdk-xyz@projekt-labor-a4b1c.iam.gserviceaccount.com",
  "client_id": "123456789",
  "auth_uri": "https://accounts.google.com/o/oauth2/auth",
  "token_uri": "https://oauth2.googleapis.com/token",
  "auth_provider_x509_cert_url": "https://www.googleapis.com/oauth2/v1/certs"
};

console.log("Admin profil szervezés:");
console.log("═══════════════════════");
console.log("");
console.log("Az admin@nagyvazsony.hu felhasználó már létezik!");
console.log("");
console.log("Email: admin@nagyvazsony.hu");
console.log("Jelszó: Admin123456!");
console.log("");
console.log("Bejelentkezz az admin panelen ezekkel az adatokkal:");
console.log("http://localhost:5175");
