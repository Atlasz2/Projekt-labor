const axios = require("axios").default;

const email = process.env.ADMIN_EMAIL;
const password = process.env.ADMIN_PASSWORD;
const apiKey = process.env.FIREBASE_WEB_API_KEY;

if (!email || !password || !apiKey) {
  console.error("Hiányzó környezeti változók. Szükséges: ADMIN_EMAIL, ADMIN_PASSWORD, FIREBASE_WEB_API_KEY");
  process.exit(1);
}

axios.post(`https://identitytoolkit.googleapis.com/v1/accounts:signUp?key=${apiKey}`, {
  email: email,
  password: password,
  returnSecureToken: true
}).then(response => {
  console.log("✅ Admin felhasználó sikeresen létrehozva!");
  console.log("");
  console.log(`Email: ${email}`);
  console.log("");
  console.log("Menj ide a bejelentkezéshez: http://localhost:5176");
  process.exit(0);
}).catch(error => {
  if (error.response?.data?.error?.message === "EMAIL_EXISTS") {
    console.log("✅ Admin felhasználó már létezik!");
    console.log("");
    console.log(`Email: ${email}`);
    console.log("");
    console.log("Menj ide a bejelentkezéshez: http://localhost:5176");
  } else {
    console.error("Hiba:", error.response?.data || error.message);
  }
  process.exit(0);
});
