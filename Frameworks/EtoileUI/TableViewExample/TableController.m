/*
	TableController.m
	
	Description forthcoming.
 
	Copyright (C) 2007 Quentin Mathe
 
	Author:  Quentin Mathe <qmathe@club-internet.fr>
	Date:  September 2007
 
	Redistribution and use in source and binary forms, with or without
	modification, are permitted provided that the following conditions are met:

	* Redistributions of source code must retain the above copyright notice,
	  this list of conditions and the following disclaimer.
	* Redistributions in binary form must reproduce the above copyright notice,
	  this list of conditions and the following disclaimer in the documentation
	  and/or other materials provided with the distribution.
	* Neither the name of the Etoile project nor the names of its contributors
	  may be used to endorse or promote products derived from this software
	  without specific prior written permission.

	THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS"
	AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
	IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE
	ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT OWNER OR CONTRIBUTORS BE
	LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR
	CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF
	SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS
	INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN
	CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE)
	ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF
	THE POSSIBILITY OF SUCH DAMAGE.
 */

#import "TableController.h"


@implementation TableController

/** All examples in this code could be rewritten with data source. They just 
	shows very basic use of EtoileUI when you don't want to deal with the extra
	burden involved by a data source. */
- (void) awakeFromNib
{	
	/*
	 * A container based on table layout
	 */

	ETLayoutItemGroup *tableItem = [tableContainer layoutItem];

	[tableItem setLayout: [ETTableLayout layout]];
	
	[[tableItem layout] setDisplayedProperties: [NSArray arrayWithObject: @"displayName"]];
	// FIXME: Should be... [tableItem setRepresentedPathBase: @"/"];
	[tableContainer setRepresentedPath: @"/"];
	
	[tableItem addItem: [ETLayoutItem itemWithValue: @"Red"]];
	[tableItem addItem: [ETLayoutItem itemWithValue: @"Green"]];
	/* Illustrate autoboxing of objects into layout items */
	[tableItem addObject: @"Blue"];
	[tableItem addObject: [NSNumber numberWithInt: 3]];
	/* Value will be image object description */
	[tableItem addObject: [NSImage imageNamed: @"NSApplication"]];
	
	/*
	 * A container using a two columns table layout
	 */
	 
	ETLayoutItemGroup *tableItem2 = [tableContainer2 layoutItem];
	ETTableLayout *tableLayout2 = [ETTableLayout layout];
	NSArray *visibleColumnIds = [NSArray arrayWithObjects: @"displayName", @"intensity", nil];
	
	[tableLayout2 setDisplayName: @"Name" forProperty: @"displayName"]; 
	[[[tableLayout2 allTableColumns] objectAtIndex: 0] setWidth: 50];
	[tableLayout2 setDisplayName: @"Intensity" forProperty: @"intensity"]; 	
	[tableLayout2 setStyle: AUTORELEASE([[NSSliderCell alloc] init])
	           forProperty: @"intensity"];
	[tableLayout2 setDisplayedProperties: visibleColumnIds];

	[tableItem2 setLayout: tableLayout2];
	// FIXME: Should be... [tableItem2 setRepresentedPathBase: @"/"];
	[tableContainer2 setRepresentedPath: @"/"];

#define NUMBER(x) [NSNumber numberWithInt: x]

	ETLayoutItem *item = [ETLayoutItem layoutItem];
	[item setValue: @"Red" forProperty: @"name"];
	[item setValue: NUMBER(10) forProperty: @"intensity"];	
	[tableItem2 addItem: item];
	
	item = [ETLayoutItem layoutItem];
	[item setValue: @"Green" forProperty: @"name"];
	[item setValue: NUMBER(100) forProperty: @"intensity"];
	[tableItem2 addItem: item];

	item = [ETLayoutItem layoutItem];
	[item setValue: @"Blue" forProperty: @"name"];
	[item setValue: NUMBER(0) forProperty: @"intensity"];	
	[tableItem2 addItem: item];
	
	[[ETPickboard localPickboard] showPickPalette];
}

- (void) applicationWillFinishLaunching: (NSNotification *)notif
{
	/*
	 * A hierarchical container using a custom outline layout based on an 
	 * existing outline view
	 */

	ETContainer *outlineContainer = [[ETContainer alloc] initWithLayoutView: outlineView];
	ETLayoutItemGroup *outlineItem = [outlineContainer layoutItem];
	NSImage *icon = [NSImage imageNamed: @"NSApplicationIcon"];
	
	[[outlineItem layout] setStyle: AUTORELEASE([[NSImageCell alloc] init])
	                        forProperty: @""];
	// FIXME: Should be... [outlineItem setRepresentedPathBase: @"/"]; /* Mandatory to handle drop */
	[outlineContainer setRepresentedPath: @"/"];

	/* This line is optional and simply avoids to update outlineItem on 
	   each -addItem: call */
	[outlineItem setAutolayout: NO];

	ETLayoutItemGroup *itemGroup = [ETLayoutItem itemGroupWithValue: icon];

	[itemGroup setValue: @"Icon!" forProperty: @"name"];
	[itemGroup addItem: [ETLayoutItem itemWithValue: icon]];
	[itemGroup addItem: [ETLayoutItem itemWithValue: icon]];
	[outlineItem addItem: itemGroup];
	[outlineItem addItem: [ETLayoutItem itemWithValue: icon]];
	
	[outlineItem setAutolayout: YES];
	[outlineItem updateLayout];
}

@end