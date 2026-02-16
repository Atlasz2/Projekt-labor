const axios = require("axios").default;

const email = "admin@nagyvazsony.hu";
const password = "Admin123456!";
const apiKey = "AIzaSyCxsLcEZymxThZP7SxN2QGTqlfHik2Ma3g";

// Test login
axios.post(`https://identitytoolkit.googleapis.com/v1/accounts:signInWithPassword?key=${apiKey}`, {
  email: email,
  password: password,
  returnSecureToken: true
}).then(response => {
  console.log("✅ Bejelentkezés sikeres!");
  console.log("");
  console.log("Email: admin@nagyvazsony.hu");
  console.log("Jelszó: Admin123456!");
  process.exit(0);
}).catch(error => {
  console.error("❌ Bejelentkezési hiba:", error.response?.data?.error?.message || error.message);
  
  // Try to create user if it doesn't exist
  if (error.response?.data?.error?.message === "INVALID_LOGIN_CREDENTIALS") {
    console.log("");
    console.log("A felhasználó nem létezik vagy hibás a jelszó.");
    console.log("Felhasználó újra létrehozása...");
    
    axios.post(`https://identitytoolkit.googleapis.com/v1/accounts:signUp?key=${apiKey}`, {
      email: email,
      password: password,
      returnSecureToken: true
    }).then(response => {
      console.log("✅ Új admin felhasználó létrehozva!");
      console.log("");
      console.log("Email: admin@nagyvazsony.hu");
      console.log("Jelszó: Admin123456!");
      process.exit(0);
    }).catch(signUpError => {
      console.error("Hiba a felhasználó létrehozásánál:", signUpError.response?.data?.error?.message);
      process.exit(1);
    });
  } else {
    process.exit(1);
  }
});
