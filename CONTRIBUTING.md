# Hozzájárulási útmutató

1. **Ág**: `feature/<rövid-leírás>` vagy `fix/<rövid-leírás>` a `main`-ből.
2. **Függőségek**: lásd a [README](README.md) „Fejlesztés” szakaszát.
3. **Ellenőrzés commit előtt**:
   ```bash
   npm run admin:lint && npm run admin:test
   npm run functions:test
   npm run mobile:analyze && npm run mobile:test
   npm run rules:test        # ha a firestore.rules vagy a functions változott (JDK 21)
   ```
4. **Commit-üzenet**: rövid, tárgyszerű (pl. `Mobil: offline csempék a térképen`).
5. **Pull request**: mi változott és hogyan tesztelhető; a CI-nak zöldnek kell lennie.
6. **Titkok**: `.env.local`, `google-services.json`, service account kulcs soha nem
   kerülhet a tárolóba.
