import { initializeApp } from 'firebase/app';
import { getAuth } from 'firebase/auth';
import { getFirestore } from 'firebase/firestore';

const firebaseConfig = {
  apiKey: 'AIzaSyCxsLcEZymxThZP7SxN2QGTqlfHik2Ma3g',
  authDomain: 'projekt-labor-a4b1c.firebaseapp.com',
  projectId: 'projekt-labor-a4b1c',
  storageBucket: 'projekt-labor-a4b1c.firebasestorage.app',
  messagingSenderId: '1062295539229',
  appId: '1:1062295539229:web:5fa4b0696c8670797840f4'
};

const app = initializeApp(firebaseConfig);
export const auth = getAuth(app);
export const db = getFirestore(app);
