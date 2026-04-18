public with sharing class TimezoneService {

    /**
     * Returns current local hour for a given timezone string
     * Uses Salesforce built-in timezone conversion — handles DST correctly
     */
    public static Integer getLocalHour(String timezoneId) {
        if (String.isBlank(timezoneId)) {
            return DateTime.now().hour();
        }
        try {
            String hourStr = DateTime.now().format('H', timezoneId);
            return Integer.valueOf(hourStr);
        } catch (Exception e) {
            return DateTime.now().hour();
        }
    }

    /**
     * Returns current local DateTime for a given timezone
     */
    public static DateTime getLocalDateTime(String timezoneId) {
        if (String.isBlank(timezoneId)) return DateTime.now();
        try {
            String formatted = DateTime.now().format(
                'yyyy-MM-dd HH:mm:ss', timezoneId
            );
            return DateTime.valueOfGmt(formatted);
        } catch (Exception e) {
            return DateTime.now();
        }
    }

    /**
     * Checks if current local time falls within shift hours
     */
    public static Boolean isWithinShift(
        String timezoneId,
        Integer startHour,
        Integer endHour
    ) {
        Integer localHour = getLocalHour(timezoneId);

        if (startHour < endHour) {
            return localHour >= startHour && localHour < endHour;
        }

        // Overnight shift (e.g. 22:00 - 06:00)
        return localHour >= startHour || localHour < endHour;
    }
}