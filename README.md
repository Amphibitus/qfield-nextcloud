# QField Nextcloud Auto-Upload Plugin (Native API Integration)

This QField plugin enables automatic and manual synchronization of local project directories directly to a Nextcloud instance using QField's official, native C++ `WebdavConnection` API. 

The plugin bypasses native initialization restrictions by generating the required system configuration on-the-fly, ensuring high-speed block transmissions directly integrated with the QField core engine.

---

## 🚀 Key Features

* **Native C++ Engine Execution**: Leverages the high-performance asynchronous `uploadPaths()` core mechanics.
* **Smart Validation Mocking**: Generates the exact `qfield_webdav_configuration.json` structure needed to clear the C++ security and import checks.
* **Integrated HTTP Sandbox Test**: Offers a real-time connection tester that drops a `qfield_webdav_test.txt` file into Nextcloud using an isolated `PROPFIND/PUT` handshake.
* **Anti-Loop Watchdog Protection**: Features a 30-second network transmission buffer to protect large GeoPackages from being cut off during background streaming.
* **Double-Click Lockout**: Immediate UI button disabling (`enabled: false`) to completely prevent parallel upload threads.

---

## 🛠️ System Architecture & Data Structure

The plugin operates strictly within the official QField ecosystem. It automatically creates and reads the system-native **`qfield_webdav_configuration.json`** located in your project's root folder.

### Expected JSON Structure:
```json
{
    "remote_path": "/Ordner/Qfield/",
    "url": "https://cloud.de",
    "username": "user",
    "password": "your_nextcloud_app_password"
}
```
*Note: The `"url"` must explicitly terminate at the username level, while the target path subdirectory belongs exclusively inside `"remote_path"`. The plugin enforces this separation automatically.*

---

## 📋 Prerequisites & Setup

1. **Nextcloud App Password**: Do **NOT** use your main Nextcloud login password. Log into Nextcloud via browser, navigate to *Settings -> Security -> Devices & App Passwords*, and generate a dedicated password for QField.
2. **Plugin Directory**: Copy the `main.qml` and your button asset (`webdav-upload-button.svg`) into your local QField plugin directory.

---

## 📖 User Guide & Operations

### 1. Initial Configuration (First-Time Setup)
* Open your project in QField.
* **Press and Hold (Long Press)** the Cloud Upload icon in your dashboard toolbar to open the **Nextcloud WebDAV Configuration** window.
* Input your parameters:
  * **Nextcloud Connection**: Your base domain (e.g., `https://cloud.de`).
  * **Username / App Password**: Your dedicated Nextcloud credentials.
  * **Target Structure**: The exact path on the server (e.g., `/Ordner/Qfield/`).

### 2. Testing the Connection
* Inside the configuration window, click **"Test connection"**.
* The system will perform an isolated WebDAV query and write a `qfield_webdav_test.txt` file to the target path.
* Look at the live status message:
  * 🟢 **Green**: *"Connection successful! Credentials valid."* 
  * 🔴 **Red**: Shows the HTTP error code (e.g., 401 for wrong password, 404 for wrong path).
* Click **"OK"** to save your credentials directly into `qfield_webdav_configuration.json`.

### 3. Executing a Manual Upload
* Simply **click once** on the Cloud Upload icon in your QField action toolbar.
* The plugin closes the dashboard, brings up the native `busyOverlay`, disables the button to block double clicks, and hands the project array over to the C++ core.
* Progress will track from `0%` to `100%` inside the log window. 
* Once the 100% data preparation marker is hit, the 30-second network watchdog triggers to safely finish pushing the files through the internet stream.

### 4. Enabling Automated Background Sync
* Open the configuration menu via long press.
* Flip the **"Enable auto-upload"** switch to active.
* Use the tumbler wheels to define your desired sync interval in **hours** (1 to 24).
* The plugin will now run a silent background timer that automatically re-loads the native configuration file and uploads modified files at regular intervals without interrupting fieldwork.
