import Foundation
import CryptoKit
import Security

func convertToCryptoKitKey(secKey: SecKey) -> P256.KeyAgreement.PrivateKey? {
    var error: Unmanaged<CFError>?
    
    guard let keyData = SecKeyCopyExternalRepresentation(secKey, &error) as Data? else {
        print("Failed to export SecKey data: \(String(describing: error?.takeRetainedValue()))")
        return nil
    }
    
    return try? P256.KeyAgreement.PrivateKey(x963Representation: keyData)
}


func loadP256KeyAgreementPrivateKey(account: String) -> P256.KeyAgreement.PrivateKey? {
    let tagData = Data(account.utf8)
    let query: [String: Any] = [
        kSecClass as String: kSecClassKey,
        kSecAttrApplicationTag as String: tagData,
        kSecReturnRef as String: true
    ]
    
    var result: AnyObject?
    let status = SecItemCopyMatching(query as CFDictionary, &result)
    
    if status == errSecSuccess, let secKey = result as! SecKey? {
        return convertToCryptoKitKey(secKey: secKey)
    }
    
    let attributes: [String: Any] = [
        kSecAttrKeyType as String: kSecAttrKeyTypeECSECPrimeRandom,
        kSecAttrKeySizeInBits as String: 256,
        kSecPrivateKeyAttrs as String: [
            kSecAttrIsPermanent as String: true,
            kSecAttrApplicationTag as String: tagData
        ]
    ]
    
    var error: Unmanaged<CFError>?
    guard let secKey = SecKeyCreateRandomKey(attributes as CFDictionary, &error) else {
        print("Failed to generate SecKey: \(String(describing: error?.takeRetainedValue()))")
        return nil
    }
    
    return convertToCryptoKitKey(secKey: secKey)
}

func encryptP2PMessage(_ message: String, peerPublicKeyBase64: String) -> String? {
    let plainData = message.data(using: .utf8)!
    
    guard let myPrivateKey = loadP256KeyAgreementPrivateKey(account: Config.appGroupIdentifier) else {
        print("Error: Local private key missing.")
        return nil
    }
    
    guard let peerKeyData = Data(base64Encoded: peerPublicKeyBase64),
          let peerPublicKey = try? P256.KeyAgreement.PublicKey(rawRepresentation: peerKeyData) else {
        print("Error: Invalid peer public key string.")
        return nil
    }
    
    do {
        let sharedSecret = try myPrivateKey.sharedSecretFromKeyAgreement(with: peerPublicKey)
        
        let symmetricKey = sharedSecret.hkdfDerivedSymmetricKey(
            using: SHA256.self,
            salt: Data(),
            sharedInfo: "P2P-Secure-Channel-Context".data(using: .utf8)!,
            outputByteCount: 32
        )
        
        let sealedBox = try AES.GCM.seal(plainData, using: symmetricKey)
        
        return sealedBox.combined?.base64EncodedString()
        
    } catch {
        print("Encryption runtime error: \(error)")
        return nil
    }
}

func decryptP2PMessage(_ encryptedBundleBase64: String, peerPublicKeyBase64: String) -> String? {
    guard let combinedData = Data(base64Encoded: encryptedBundleBase64),
          let sealedBox = try? AES.GCM.SealedBox(combined: combinedData) else {
        print("Error: Encrypted payload is corrupted.")
        return nil
    }
    
    guard let myPrivateKey = loadP256KeyAgreementPrivateKey(account: Config.appGroupIdentifier) else {
        print("Error: Local private key missing.")
        return nil
    }
    
    guard let peerKeyData = Data(base64Encoded: peerPublicKeyBase64),
          let peerPublicKey = try? P256.KeyAgreement.PublicKey(rawRepresentation: peerKeyData) else {
        print("Error: Invalid peer public key string.")
        return nil
    }
    
    do {
        let sharedSecret = try myPrivateKey.sharedSecretFromKeyAgreement(with: peerPublicKey)
        
        let symmetricKey = sharedSecret.hkdfDerivedSymmetricKey(
            using: SHA256.self,
            salt: Data(),
            sharedInfo: "P2P-Secure-Channel-Context".data(using: .utf8)!,
            outputByteCount: 32
        )
        
        let decryptedData = try AES.GCM.open(sealedBox, using: symmetricKey)
        
        return String(data: decryptedData, encoding: .utf8)
        
    } catch {
        print("Decryption failed. The message may have been tampered with: \(error)")
        return nil
    }
}


func getPublicKey(from privateSecKey: SecKey) -> SecKey? {
    return SecKeyCopyPublicKey(privateSecKey)
}

func deleteP256KeyAgreementPrivateKey(account: String) -> Bool {
    let tagData = Data(account.utf8)
    let query: [String: Any] = [
        kSecClass as String: kSecClassKey,
        kSecAttrApplicationTag as String: tagData
    ]
    
    let status = SecItemDelete(query as CFDictionary)
    
    if status == errSecSuccess {
        print("Successfully deleted key for account: \(account)")
        return true
    } else if status == errSecItemNotFound {
        print("Key not found in keychain for account: \(account)")
        return true
    } else {
        print("Failed to delete key with status: \(status)")
        return false
    }
}
