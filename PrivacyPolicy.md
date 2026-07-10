# Privacy Policy

**Effective Date:** July 9, 2026

This Privacy Policy explains how our peer-to-peer chat application ("Between", "we", "us", or "our") collects, uses, and protects your information. We are committed to your privacy and have designed this app from the ground up to minimize data collection and ensure your communications remain private.

## 1. Information We Do Not Collect

Our app is built on a decentralized, peer-to-peer architecture using WebRTC. 

*   **No Message Storage:** We do not read, intercept, or store any of your chat messages, images, or files. All communication is directly transmitted between you and your peer.
*   **End-to-End Encryption:** Your messages are encrypted before they leave your device and can only be decrypted by the intended recipient.
*   **No Analytics or Tracking:** We do not use third-party analytics, advertising SDKs, or tracking software to monitor your usage of the app.
*   **No Accounts:** We do not require you to create an account, provide an email address, or submit a phone number to use the app.

## 2. Information Handled by the Signaling Server

To establish a peer-to-peer connection, the app temporarily communicates with a public signaling server.

*   **Connection Data:** The signaling server temporarily processes network routing information (such as IP addresses, ICE candidates, and SDP offers/answers) strictly for the purpose of helping two devices find each other on the internet.
*   **No Persistence:** Once a direct WebRTC connection is established between peers, the signaling server drops out of the communication loop. This temporary connection data is not stored, logged, or tied to your identity.

## 3. Data Stored Locally on Your Device

All of your personal data is stored locally on your own device using Apple's secure data storage (SwiftData). This includes:

*   **Chat History:** Your sent and received messages.
*   **Contacts:** Any peers you save to your contact list (including names, WebRTC IDs, and profile pictures).

You have full control over this data. You can delete your local database at any time by accessing the data management options within the app.

## 4. Third-Party Links and Services

The app connects to a default public signaling server hosted on Oracle Cloud Infrastructure (OCI). While we operate this server, we do not collect or log personal data through it. You also have the option to configure the app to use your own custom signaling server if you prefer.

## 5. Changes to This Privacy Policy

We may update this Privacy Policy from time to time. Any changes will be reflected in this document with an updated "Effective Date."

## 6. Contact Us

If you have any questions or concerns about this Privacy Policy or our data practices, please contact us at:

report@coolstone.dev