const axios = require("axios").default;

const email = process.env.TEST_USER_EMAIL;
const password = process.env.TEST_USER_PASSWORD;
const apiKey = process.env.FIREBASE_WEB_API_KEY;

if (!email || !password || !apiKey) {
  console.error("Hiányzó környezeti változók. Szükséges: TEST_USER_EMAIL, TEST_USER_PASSWORD, FIREBASE_WEB_API_KEY");
  process.exit(1);
}

axios.post(`https://identitytoolkit.googleapis.com/v1/accounts:signUp?key=${apiKey}`, {
  email: email,
  password: password,
  returnSecureToken: true
}).then(response => {
  console.log("✅ Új felhasználó sikeresen létrehozva!");
  console.log("");
  console.log(`Email: ${email}`);
  console.log("");
  console.log("Bejelentkezz az admin panelen: http://localhost:5176");
  process.exit(0);
}).catch(error => {
  if (error.response?.data?.error?.message === "EMAIL_EXISTS") {
    console.log("✅ A felhasználó már létezik!");
    console.log("");
    console.log(`Email: ${email}`);
    console.log("");
    console.log("Bejelentkezz az admin panelen: http://localhost:5176");
  } else {
    console.error("❌ Hiba:", error.response?.data?.error?.message || error.message);
  }
  process.exit(0);
});
