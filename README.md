# Ijwi (Class Election)

Ijwi is a class election app where students vote for a representative and see the live results. It signs users in with Firebase Authentication, and each user's data is saved in Cloud Firestore under their own id, so two accounts never see each other's data, and every change appears live.

## Screenshots

### 1. Login
![Login](screenshots/login.png)

### 2. My data in Firestore
![My data in Firestore](screenshots/console.png)

### 3. Live update
Before the change in the console:

![Live update, before](screenshots/livebefore.png)

After the change, without restarting the app:

![Live update, after](screenshots/live.png)

### 4. Privacy between accounts
First account:

![First account](screenshots/deniedone.png)

Second account sees nothing of the first account's data:

![Second account sees nothing of mine](screenshots/denied.png)