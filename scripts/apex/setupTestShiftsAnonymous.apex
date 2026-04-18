// ----------------------------
// CREATE TEST SHIFTS
// Run this in Developer Console → Execute Anonymous
// ----------------------------

// Get 4 users from your org
List<User> users = [
    SELECT Id, Name
    FROM User
    WHERE IsActive = true
    AND Profile.Name != 'System Administrator'
    LIMIT 4
];

if (users.size() < 4) {
    System.debug('❌ Need at least 4 active non-admin users!');
    return;
}

List<Shift__c> shifts = new List<Shift__c>{

    new Shift__c(
        Name = 'Istanbul Morning Shift',
        Assigned_User__c = users[0].Id,
        Timezone__c = 'Europe/Istanbul',
        Start_Hour__c = 8,
        End_Hour__c = 16,
        Is_Active__c = true,
        Current_Lead_Count__c = 0
    ),
    new Shift__c(
        Name = 'Lagos Afternoon Shift',
        Assigned_User__c = users[1].Id,
        Timezone__c = 'Africa/Lagos',
        Start_Hour__c = 9,
        End_Hour__c = 17,
        Is_Active__c = true,
        Current_Lead_Count__c = 0
    ),
    new Shift__c(
        Name = 'Berlin Evening Shift',
        Assigned_User__c = users[2].Id,
        Timezone__c = 'Europe/Berlin',
        Start_Hour__c = 14,
        End_Hour__c = 22,
        Is_Active__c = true,
        Current_Lead_Count__c = 0
    ),
    new Shift__c(
        Name = 'New York Night Shift',
        Assigned_User__c = users[3].Id,
        Timezone__c = 'America/New_York',
        Start_Hour__c = 20,
        End_Hour__c = 4,
        Is_Active__c = true,
        Current_Lead_Count__c = 0
    )
};

insert shifts;

System.debug('✅ Shifts created:');
for (Shift__c s : shifts) {
    System.debug('→ ' + s.Name);
}
