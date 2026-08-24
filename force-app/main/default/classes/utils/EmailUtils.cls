public with sharing class EmailUtils {
    
    /**
     * @description
     * Normalize email by trimming and converting to lowercase
     *
     * @param rawEmail incoming email string
     * @return normalized email
     */
    public static String normalizeEmail(String rawEmail) {
        
        if (String.isBlank(rawEmail)) {
            return null;
        }
        
        String email = rawEmail.trim().toLowerCase();
        
        if (!email.contains('@')) {
            return null;
        }
        
        return email;
    }
    
    
    /**
     * @description
     * Extract domain from normalized email
     *
     * Example:
     * partner@bursa.com → bursa.com
     *
     * @param normalizedEmail normalized email string
     * @return domain value
     */
    public static String extractDomain(String normalizedEmail) {
        
        if (String.isBlank(normalizedEmail)) {
            return null;
        }
        
        if (!normalizedEmail.contains('@')) {
            return null;
        }
        
        String domain = normalizedEmail.substringAfter('@');
        
        if (String.isBlank(domain)) {
            return null;
        }
        
        return domain.trim().toLowerCase();
    }
    
}