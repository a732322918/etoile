#include <LuceneKit/Document/LCDateTools.h>
#include <LuceneKit/GNUstep/GNUstep.h>

/**
* Provides support for converting dates to strings and vice-versa.
 * The strings are structured so that lexicographic sorting orders 
 * them by date, which makes them suitable for use as field values 
 * and search terms.
 * 
 * <P>This class also helps you to limit the resolution of your dates. Do not
 * save dates with a finer resolution than you really need, as then
 * RangeQuery and PrefixQuery will require more memory and become slower.
 * 
 * <P>Compared to {@link DateField} the strings generated by the methods
 * in this class take slightly more space, unless your selected resolution
 * is set to <code>Resolution.DAY</code> or lower.
 */
@implementation NSString (LuceneKit_Document_Date)

/**
* Converts a Date to a string suitable for indexing.
 * 
 * @param date the date to be converted
 * @param resolution the desired resolution, see
 *  {@link #round(Date, DateTools.Resolution)}
 * @return a string in format <code>yyyyMMddHHmmssSSS</code> or shorter,
 *  depeding on <code>resolution</code>
 */
+ (id) stringWithCalendarDate: (NSCalendarDate *) date
                   resolution: (LCResolution) res;
{
	return [NSString stringWithTimeIntervalSince1970: [date timeIntervalSince1970]
										  resolution: res];
}

/**
* Converts a millisecond time to a string suitable for indexing.
 * 
 * @param time the date expressed as milliseconds since January 1, 1970, 00:00:00 GMT
 * @param resolution the desired resolution, see
 *  {@link #round(long, DateTools.Resolution)}
 * @return a string in format <code>yyyyMMddHHmmssSSS</code> or shorter,
 *  depeding on <code>resolution</code>
 */
+ (id) stringWithTimeIntervalSince1970: (NSTimeInterval) time
                            resolution: (LCResolution) resolution;
{
	NSTimeInterval interval;
	NSCalendarDate *date;
	NSString *pattern;
	date = [NSCalendarDate dateWithTimeIntervalSince1970: time];
	interval = [date timeIntervalSince1970WithResolution: resolution];
	date = [NSCalendarDate dateWithTimeIntervalSince1970: interval];
	
	if (resolution == LCResolution_YEAR) {
		pattern = @"%Y";
	} else if (resolution == LCResolution_MONTH) {
		pattern = @"%Y%m";
	} else if (resolution == LCResolution_DAY) {
		pattern = @"%Y%m%d";
	} else if (resolution == LCResolution_HOUR) {
		pattern = @"%Y%m%d%H";
	} else if (resolution == LCResolution_MINUTE) {
		pattern = @"%Y%m%d%H%M";
	} else if (resolution == LCResolution_SECOND) {
		pattern = @"%Y%m%d%H%M%S";
	} else if (resolution == LCResolution_MILLISECOND) {
		pattern = @"%Y%m%d%H%M%S%F";
	} else {
		return nil; // Unknown Resolution
	}
	
	return [date descriptionWithCalendarFormat: pattern];
}

/**
* Converts a string produced by <code>timeToString</code> or
 * <code>dateToString</code> back to a time, represented as the
 * number of milliseconds since January 1, 1970, 00:00:00 GMT.
 * 
 * @param dateString the date string to be converted
 * @return the number of milliseconds since January 1, 1970, 00:00:00 GMT
 * @throws ParseException if <code>dateString</code> is not in the 
 *  expected format 
 */
- (NSTimeInterval) timeIntervalSince1970
{
	return [[self calendarDate] timeIntervalSince1970];
}

/**
* Converts a string produced by <code>timeToString</code> or
 * <code>dateToString</code> back to a time, represented as a
 * Date object.
 * 
 * @param dateString the date string to be converted
 * @return the parsed time as a Date object 
 * @throws ParseException if <code>dateString</code> is not in the 
 *  expected format 
 */
- (NSCalendarDate *) calendarDate;
{
	NSString *pattern = nil;
	int len = [self length];
	switch(len)
	{
		case 4:
			pattern = @"%Y";
			break;
		case 6:
			pattern = @"%Y%m";
			break;
		case 8:
			pattern = @"%Y%m%d";
			break;
		case 10:
			pattern = @"%Y%m%d%H";
			break;
		case 12:
			pattern = @"%Y%m%d%H%M";
			break;
		case 14:
			pattern = @"%Y%m%d%H%M%S";
			break;
		case 17:
			pattern = @"%Y%m%d%H%M%S%F";
			break;
		default: 
			return nil; // Not Valid Date String
	}
	
	return [NSCalendarDate dateWithString: self calendarFormat: pattern];
}

@end

@implementation NSCalendarDate (LuceneKit_Document_Date)

/**
* Limit a date's resolution. For example, the date <code>1095767411000</code>
 * (which represents 2004-09-21 13:50:11) will be changed to 
 * <code>1093989600000</code> (2004-09-01 00:00:00) when using
 * <code>Resolution.MONTH</code>.
 * 
 * @param resolution The desired resolution of the date to be returned
 * @return the date with all values more precise than <code>resolution</code>
 *  set to 0 or 1, expressed as milliseconds since January 1, 1970, 00:00:00 GMT
 */
- (NSTimeInterval) timeIntervalSince1970WithResolution: (LCResolution) res
{
	return [[self dateWithResolution: res] timeIntervalSince1970];
}

/**
* Limit a date's resolution. For example, the date <code>2004-09-21 13:50:11</code>
 * will be changed to <code>2004-09-01 00:00:00</code> when using
 * <code>Resolution.MONTH</code>. 
 * 
 * @param resolution The desired resolution of the date to be returned
 * @return the date with all values more precise than <code>resolution</code>
 *  set to 0 or 1
 */
- (NSCalendarDate *) dateWithResolution: (LCResolution) res
{
	switch(res)
	{
		case LCResolution_YEAR:
			return [NSCalendarDate dateWithYear: [self yearOfCommonEra]
										  month: 1
											day: 1
										   hour: 0
										 minute: 0
										 second: 0
									   timeZone: nil];
		case LCResolution_MONTH:
			return [NSCalendarDate dateWithYear: [self yearOfCommonEra]
										  month: [self monthOfYear]
											day: 1
										   hour: 0
										 minute: 0
										 second: 0
									   timeZone: nil];
		case LCResolution_DAY:
			return [NSCalendarDate dateWithYear: [self yearOfCommonEra]
										  month: [self monthOfYear]
											day: [self dayOfMonth]
										   hour: 0
										 minute: 0
										 second: 0
									   timeZone: nil];
		case LCResolution_HOUR:
			return [NSCalendarDate dateWithYear: [self yearOfCommonEra]
										  month: [self monthOfYear]
											day: [self dayOfMonth]
										   hour: [self hourOfDay]
										 minute: 0
										 second: 0
									   timeZone: nil];
		case LCResolution_MINUTE:
			return [NSCalendarDate dateWithYear: [self yearOfCommonEra]
										  month: [self monthOfYear]
											day: [self dayOfMonth]
										   hour: [self hourOfDay]
										 minute: [self minuteOfHour]
										 second: 0
									   timeZone: nil];
		case LCResolution_SECOND: 
			return [NSCalendarDate dateWithYear: [self yearOfCommonEra]
										  month: [self monthOfYear]
											day: [self dayOfMonth]
										   hour: [self hourOfDay]
										 minute: [self minuteOfHour]
										 second: [self secondOfMinute]
									   timeZone: nil];
		case LCResolution_MILLISECOND:
			return AUTORELEASE([self copy]);
			// don't cut off anything
		default:
			return nil; // Error;
	}
}

@end

#ifdef HAVE_UKTEST

#include <UnitKit/UnitKit.h>

@interface TestDateTools: NSObject <UKTest>
@end

@implementation TestDateTools

- (NSString *) isoFormat: (NSCalendarDate *) date
{
	return [date descriptionWithCalendarFormat: @"%Y-%m-%d %H:%M:%S:%F"];
}

- (void) testStringToDate
{
	NSCalendarDate *date = [@"2004" calendarDate];
	UKStringsEqual(@"2004-01-01 00:00:00:000", [self isoFormat: date]);
	date = [@"20040705" calendarDate];
	UKStringsEqual(@"2004-07-05 00:00:00:000", [self isoFormat: date]);
	date = [@"200407050910" calendarDate];
	UKStringsEqual(@"2004-07-05 09:10:00:000", [self isoFormat: date]);
	date = [@"20040705091055990" calendarDate];
	UKStringsEqual(@"2004-07-05 09:10:55:990", [self isoFormat: date]);
	
#if 0
    try {
		d = DateTools.stringToDate("97");    // no date
		fail();
    } catch(ParseException e) { /* expected excpetion */ }
    try {
		d = DateTools.stringToDate("200401011235009999");    // no date
		fail();
    } catch(ParseException e) { /* expected excpetion */ }
    try {
		d = DateTools.stringToDate("aaaa");    // no date
		fail();
    } catch(ParseException e) { /* expected excpetion */ }
#endif
}

- (void) testStringToTime
{
	NSTimeInterval t = [@"197001010000" timeIntervalSince1970];
	NSCalendarDate *d = [NSCalendarDate dateWithYear: 1970
											   month: 1 day: 1 hour: 0 minute: 0 second: 0
											timeZone: nil];
	UKTrue(t == [d timeIntervalSince1970]);
	t = [@"198002021105" timeIntervalSince1970];
	d = [NSCalendarDate dateWithYear: 1980
							   month: 2 day: 2 hour: 11 minute: 5 second: 0
							timeZone: nil];
	UKTrue(t == [d timeIntervalSince1970]);
}

- (void) testDateAndTimeToString
{
	NSCalendarDate *d = [NSCalendarDate dateWithYear: 2004
											   month: 2 day: 3 hour: 22 minute: 8 second: 56
											timeZone: nil];
	NSString *dateString = [NSString stringWithCalendarDate: d
												 resolution: LCResolution_YEAR];;
												 UKStringsEqual(@"2004", dateString);
												 UKStringsEqual(@"2004-01-01 00:00:00:000", [self isoFormat: [dateString calendarDate]]);
												 
												 dateString = [NSString stringWithCalendarDate: d
																					resolution: LCResolution_MONTH];;
																					UKStringsEqual(@"200402", dateString);
																					UKStringsEqual(@"2004-02-01 00:00:00:000", [self isoFormat: [dateString calendarDate]]);
																					
																					dateString = [NSString stringWithCalendarDate: d
																													   resolution: LCResolution_DAY];;
																													   UKStringsEqual(@"20040203", dateString);
																													   UKStringsEqual(@"2004-02-03 00:00:00:000", [self isoFormat: [dateString calendarDate]]);
																													   
																													   dateString = [NSString stringWithCalendarDate: d
																																						  resolution: LCResolution_HOUR];;
																																						  UKStringsEqual(@"2004020322", dateString);
																																						  UKStringsEqual(@"2004-02-03 22:00:00:000", [self isoFormat: [dateString calendarDate]]);
																																						  
																																						  dateString = [NSString stringWithCalendarDate: d
																																															 resolution: LCResolution_MINUTE];;
																																															 UKStringsEqual(@"200402032208", dateString);
																																															 UKStringsEqual(@"2004-02-03 22:08:00:000", [self isoFormat: [dateString calendarDate]]);
																																															 
																																															 dateString = [NSString stringWithCalendarDate: d
																																																								resolution: LCResolution_SECOND];;
																																																								UKStringsEqual(@"20040203220856", dateString);
																																																								UKStringsEqual(@"2004-02-03 22:08:56:000", [self isoFormat: [dateString calendarDate]]);
																																																								
#if 0
																																																								dateString = DateTools.dateToString(cal.getTime(), DateTools.Resolution.MILLISECOND);
																																																								assertEquals("20040203220856333", dateString);
																																																								assertEquals("2004-02-03 22:08:56:333", isoFormat(DateTools.stringToDate(dateString)));
#endif
																																																								
																																																								// date before 1970:
																																																								d = [NSCalendarDate dateWithYear: 1961
																																																														   month: 3 day: 5 hour: 23 minute: 9 second: 51
																																																														timeZone: nil];
																																																								dateString = [NSString stringWithCalendarDate: d
																																																																   resolution: LCResolution_SECOND];;
																																																																   UKStringsEqual(@"19610305230951", dateString);
																																																																   UKStringsEqual(@"1961-03-05 23:09:51:000", [self isoFormat: [dateString calendarDate]]);
																																																																   
																																																																   dateString = [NSString stringWithCalendarDate: d
																																																																									  resolution: LCResolution_HOUR];;
																																																																									  UKStringsEqual(@"1961030523", dateString);
																																																																									  UKStringsEqual(@"1961-03-05 23:00:00:000", [self isoFormat: [dateString calendarDate]]);
																																																																									  
																																																																									  // timeToString:
																																																																									  d = [NSCalendarDate dateWithYear: 1970
																																																																																 month: 1 day: 1 hour: 0 minute: 0 second: 0 
																																																																															  timeZone: nil];
																																																																									  dateString = [NSString stringWithTimeIntervalSince1970: [d timeIntervalSince1970]
																																																																																				  resolution: LCResolution_MILLISECOND];;
																																																																																				  UKStringsEqual(@"19700101000000000", dateString);
																																																																																				  
																																																																																				  d = [NSCalendarDate dateWithYear: 1970
																																																																																											 month: 1 day: 1 hour: 1 minute: 2 second: 3 
																																																																																										  timeZone: nil];
																																																																																				  dateString = [NSString stringWithTimeIntervalSince1970: [d timeIntervalSince1970]
																																																																																															  resolution: LCResolution_MILLISECOND];;
																																																																																															  UKStringsEqual(@"19700101010203000", dateString);
}

- (void) testRound
{
	NSCalendarDate *d = [NSCalendarDate dateWithYear: 2004
											   month: 2 day: 3 hour: 22 minute: 8 second: 56
											timeZone: nil];
	UKStringsEqual(@"2004-02-03 22:08:56:000", [self isoFormat: d]);
	
	NSCalendarDate *r = [d dateWithResolution: LCResolution_YEAR];
	UKStringsEqual(@"2004-01-01 00:00:00:000", [self isoFormat: r]);
	
	r = [d dateWithResolution: LCResolution_MONTH];
	UKStringsEqual(@"2004-02-01 00:00:00:000", [self isoFormat: r]);
	
	r = [d dateWithResolution: LCResolution_DAY];
	UKStringsEqual(@"2004-02-03 00:00:00:000", [self isoFormat: r]);
	
	r = [d dateWithResolution: LCResolution_HOUR];
	UKStringsEqual(@"2004-02-03 22:00:00:000", [self isoFormat: r]);
	
	r = [d dateWithResolution: LCResolution_MINUTE];
	UKStringsEqual(@"2004-02-03 22:08:00:000", [self isoFormat: r]);
	
	r = [d dateWithResolution: LCResolution_SECOND];
	UKStringsEqual(@"2004-02-03 22:08:56:000", [self isoFormat: r]);
	
#if 0
    Date dateMillisecond = DateTools.round(date, DateTools.Resolution.MILLISECOND);
    assertEquals("2004-02-03 22:08:56:333", isoFormat(dateMillisecond));
#endif
	
    // long parameter:
	NSTimeInterval t = [d timeIntervalSince1970WithResolution: LCResolution_YEAR];
	r = [NSCalendarDate dateWithTimeIntervalSince1970: t];
	UKStringsEqual(@"2004-01-01 00:00:00:000", [self isoFormat: r]);
	
	t = [d timeIntervalSince1970WithResolution: LCResolution_MILLISECOND];
	r = [NSCalendarDate dateWithTimeIntervalSince1970: t];
	UKStringsEqual(@"2004-02-03 22:08:56:000", [self isoFormat: r]);
}

@end

#endif /* HAVE_UKTEST */
