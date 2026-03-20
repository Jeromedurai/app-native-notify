using System.Security.Cryptography;
using System.Text;

namespace AppNativeNotification.Utilities;

/// <summary>
/// Provides encryption and decryption functionality for sensitive data
/// </summary>
public static class Encryption
{
    private const string EncryptionKey = "XtraChef@2024$SecureKey#12345";

    /// <summary>
    /// Encrypts or decrypts a string based on the decrypt parameter
    /// </summary>
    /// <param name="text">The text to encrypt or decrypt</param>
    /// <param name="decrypt">True to decrypt, false to encrypt</param>
    /// <returns>The encrypted or decrypted string</returns>
    public static string EnDecrypt(string text, bool decrypt)
    {
        if (string.IsNullOrEmpty(text))
            return text;

        try
        {
            if (decrypt)
                return DecryptString(text);
            else
                return EncryptString(text);
        }
        catch
        {
            // If decryption fails, return original text (it might not be encrypted)
            return text;
        }
    }

    private static string EncryptString(string plainText)
    {
        byte[] key = DeriveKeyFromPassword(EncryptionKey);

        using var aes = Aes.Create();
        aes.Key = key;
        aes.GenerateIV();

        using var encryptor = aes.CreateEncryptor(aes.Key, aes.IV);
        using var msEncrypt = new MemoryStream();

        // Prepend IV to the encrypted data
        msEncrypt.Write(aes.IV, 0, aes.IV.Length);

        using (var csEncrypt = new CryptoStream(msEncrypt, encryptor, CryptoStreamMode.Write))
        using (var swEncrypt = new StreamWriter(csEncrypt))
        {
            swEncrypt.Write(plainText);
        }

        return Convert.ToBase64String(msEncrypt.ToArray());
    }

    private static string DecryptString(string cipherText)
    {
        byte[] buffer = Convert.FromBase64String(cipherText);
        byte[] key = DeriveKeyFromPassword(EncryptionKey);

        using var aes = Aes.Create();
        aes.Key = key;

        // Extract IV from the beginning of the buffer
        byte[] iv = new byte[aes.IV.Length];
        Array.Copy(buffer, 0, iv, 0, iv.Length);
        aes.IV = iv;

        using var decryptor = aes.CreateDecryptor(aes.Key, aes.IV);
        using var msDecrypt = new MemoryStream(buffer, iv.Length, buffer.Length - iv.Length);
        using var csDecrypt = new CryptoStream(msDecrypt, decryptor, CryptoStreamMode.Read);
        using var srDecrypt = new StreamReader(csDecrypt);

        return srDecrypt.ReadToEnd();
    }

    private static byte[] DeriveKeyFromPassword(string password)
    {
        var salt = Encoding.UTF8.GetBytes("XtraChefSalt");
        using var deriveBytes = new Rfc2898DeriveBytes(password, salt, 10000, HashAlgorithmName.SHA256);
        return deriveBytes.GetBytes(32); // 256 bits for AES-256
    }
}
