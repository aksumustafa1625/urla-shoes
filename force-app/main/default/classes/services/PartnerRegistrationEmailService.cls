public with sharing class PartnerRegistrationEmailService {
    
    /**
     * Bu metod aynı domain için daha önce mail gönderilip gönderilmediğini kontrol eder.
     */
    public static Boolean shouldSendRegistrationEmail(String domain){
        List<Reseller_Match_Log__c> logs = [
            SELECT Id
            FROM Reseller_Match_Log__c
            WHERE Extracted_Domain__c = :domain
            AND Registration_Email_Sent__c = true
            LIMIT 1
        ];
        return logs.isEmpty();
    }
    
    /**
     * Bu metod partner'a tek kullanımlık (Magic Link) içeren şık bir HTML mail gönderir.
     */
    public static void sendRegistrationEmail(String email){
        
        // 1. En güncel Log kaydını buluyoruz
        List<Reseller_Match_Log__c> logs = [
            SELECT Id 
            FROM Reseller_Match_Log__c 
            WHERE Incoming_Email__c = :email 
            ORDER BY CreatedDate DESC 
            LIMIT 1
        ];
        
        if(logs.isEmpty()) {
            System.debug('HATA: Log bulunamadığı için mail gönderilemedi.');
            return;
        }
        
        Reseller_Match_Log__c logToUpdate = logs[0];
        
        // 2. Güvenli ve benzersiz Token oluşturma
        String uniqueToken = UUID.randomUUID().toString();
        
        // 3. Log kaydını güncelleme
        logToUpdate.Verification_Token__c = uniqueToken;
        logToUpdate.Token_Used__c = false;
        logToUpdate.Token_Expiration__c = System.now().addDays(7); // 7 günlük geçerlilik
        logToUpdate.Registration_Email_Sent__c = true;
        
        update logToUpdate;
        
        // 4. Magic Link Hazırlama (İç link - Daha sonra Experience Cloud linki ile değişecek)
        String magicLink = 'https://your-org.develop.lightning.force.com/flow/Partner_Registration_Flow?token=' + uniqueToken;
        
        // 5. Şık HTML E-posta Hazırlama
        Messaging.SingleEmailMessage mail = new Messaging.SingleEmailMessage();
        mail.setToAddresses(new List<String>{email});
        mail.setSubject('Urla Shoes: Complete Your Partner Registration');
        
        // HTML Body - Profesyonel Buton Tasarımı
        String htmlBody = '<div style="font-family: \'Segoe UI\', Tahoma, Geneva, Verdana, sans-serif; line-height: 1.6; color: #333; max-width: 600px; border: 1px solid #eee; padding: 20px; border-radius: 10px;">' +
            '<h2 style="color: #0070d2;">Hello,</h2>' +
            '<p>We noticed an opportunity associated with your email domain. Since your company is not yet registered in our <strong>Urla Shoes Reseller System</strong>, we invite you to complete your registration to proceed.</p>' +
            
            '<div style="background-color: #f9f9f9; padding: 15px; border-left: 5px solid #0070d2; margin: 20px 0;">' +
                '<strong>Important:</strong> This invitation is secure and valid for only <strong>2 days</strong>. It can only be used once.' +
            '</div>' +
            
            '<div style="text-align: center; margin: 35px 0;">' +
                '<a href="' + magicLink + '" style="background-color: #0070d2; color: #ffffff; padding: 15px 30px; text-decoration: none; border-radius: 5px; font-weight: bold; font-size: 16px; display: inline-block;">' +
                    'Complete Registration Form' +
                '</a>' +
            '</div>' +
            
            '<p style="font-size: 13px; color: #666;">If the button above does not work, please copy and paste the following link into your browser:</p>' +
            '<p style="font-size: 11px; color: #999; word-break: break-all;">' + magicLink + '</p>' +
            
            '<hr style="border: none; border-top: 1px solid #eee; margin: 25px 0;"/>' +
            '<p style="font-size: 14px;">Best regards,<br/><strong>Urla Shoes Team</strong></p>' +
        '</div>';
        
        mail.setHtmlBody(htmlBody);
        
        // Plain text versiyonu (HTML desteklemeyen eski cihazlar için güvenlik önlemi)
        mail.setPlainTextBody('Please visit the following link to register: ' + magicLink);
        
        // 6. E-postayı Gönder
        if(!Test.isRunningTest()){
            Messaging.sendEmail(new Messaging.SingleEmailMessage[]{mail});
        }
        
        System.debug('Profesyonel Mail Gönderildi. Token: ' + uniqueToken);
    }
}