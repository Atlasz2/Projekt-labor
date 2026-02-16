const axios = require("axios").default;

const email = "test@test.com";
const password = "Test123456!";
const apiKey = "AIzaSyCxsLcEZymxThZP7SxN2QGTqlfHik2Ma3g";

// Create new user
axios.post(`https://identitytoolkit.googleapis.com/v1/accounts:signUp?key=${apiKey}`, {
  email: email,
  password: password,
  returnSecureToken: true
}).then(response => {
  console.log("✅ Új felhasználó sikeresen létrehozva!");
  console.log("");
  console.log("Email: test@test.com");
  console.log("Jelszó: Test123456!");
  console.log("");
  console.log("Bejelentkezz az admin panelen: http://localhost:5176");
  process.exit(0);
}).catch(error => {
  if (error.response?.data?.error?.message === "EMAIL_EXISTS") {
    console.log("✅ A felhasználó már létezik!");
    console.log("");
    console.log("Email: test@test.com");
    console.log("Jelszó: Test123456!");
    console.log("");
    console.log("Bejelentkezz az admin panelen: http://localhost:5176");
  } else {
    console.error("❌ Hiba:", error.response?.data?.error?.message || error.message);
  }
  process.exit(0);
});
