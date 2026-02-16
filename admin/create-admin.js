const axios = require("axios").default;

const email = "admin@nagyvazsony.hu";
const password = "Admin123456!";
const apiKey = "AIzaSyCxsLcEZymxThZP7SxN2QGTqlfHik2Ma3g";

axios.post(`https://identitytoolkit.googleapis.com/v1/accounts:signUp?key=${apiKey}`, {
  email: email,
  password: password,
  returnSecureToken: true
}).then(response => {
  console.log("✅ Admin felhasználó sikeresen létrehozva!");
  console.log("");
  console.log("Email: admin@nagyvazsony.hu");
  console.log("Jelszó: Admin123456!");
  console.log("");
  console.log("Menj ide a bejelentkezéshez: http://localhost:5176");
  process.exit(0);
}).catch(error => {
  if (error.response?.data?.error?.message === "EMAIL_EXISTS") {
    console.log("✅ Admin felhasználó már létezik!");
    console.log("");
    console.log("Email: admin@nagyvazsony.hu");
    console.log("Jelszó: Admin123456!");
    console.log("");
    console.log("Menj ide a bejelentkezéshez: http://localhost:5176");
  } else {
    console.error("Hiba:", error.response?.data || error.message);
  }
  process.exit(0);
});
