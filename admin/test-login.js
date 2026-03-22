const axios = require("axios").default;

const email = process.env.ADMIN_EMAIL;
const password = process.env.ADMIN_PASSWORD;
const apiKey = process.env.FIREBASE_WEB_API_KEY;

if (!email || !password || !apiKey) {
  console.error("Hiányzó környezeti változók. Szükséges: ADMIN_EMAIL, ADMIN_PASSWORD, FIREBASE_WEB_API_KEY");
  process.exit(1);
}

axios.post(`https://identitytoolkit.googleapis.com/v1/accounts:signInWithPassword?key=${apiKey}`, {
  email: email,
  password: password,
  returnSecureToken: true
}).then(response => {
  console.log("✅ Bejelentkezés sikeres!");
  console.log("");
  console.log(`Email: ${email}`);
  process.exit(0);
}).catch(error => {
  console.error("❌ Bejelentkezési hiba:", error.response?.data?.error?.message || error.message);
  process.exit(1);
});
