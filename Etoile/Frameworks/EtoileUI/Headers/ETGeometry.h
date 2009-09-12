/** <title>Geometry</title>

	<abstract>Geometry utility functions and constants.</abstract>

	Copyright (C) 2008 Quentin Mathe
 
	Author:  Quentin Mathe <qmathe@club-internet.fr>
	Date:  December 2008
	License:  Modified BSD (see COPYING)
 */

#import <Foundation/Foundation.h>
#import <AppKit/AppKit.h>
// TODO: Remove once geometry functions declared in NSView+Etoile have been 
// moved in ETGeometry as expected. In the meantime, this avoids to import 
// NSView+Etoile.h when only ETGeometry.h should be imported.
#import <EtoileUI/NSView+Etoile.h>

/** The null point which is not equal to NSZeroPoint. It can be returned 
when a point value is undefined and is a nil-like marker for NSPoint primitive. */
extern const NSPoint ETNullPoint;
/** The null size which is not equal to NSZeroSize. It can be returned 
when a size value is undefined and is a nil-like marker for NSSize primitive. */
extern const NSSize ETNullSize;
/** The null rectangle which is not equal to NSZeroRect. It can be returned 
when a rect value is undefined and is a nil-like marker for NSRect primitive. */
extern const NSRect ETNullRect;

/** Returns whether the given point is equal to ETNullPoint. */
static inline BOOL ETIsNullPoint(NSPoint aPoint)
{
	return NSEqualPoints(aPoint, ETNullPoint);
}

/** Returns whether rect is equal to ETNullRect. */
static inline BOOL ETIsNullRect(NSRect rect)
{
	return NSEqualRects(rect, ETNullRect);
}

/** Returns a rect that uses aSize as its size and centered inside the given rect.

The returned rect is expressed relative the given rect parent coordinate space.<br />
To get a rect expressed relative the the given rect itself, pass a rect with a zero 
origin: 
<code>
NSRect inRect = NSMakeRect(40, 50, 100, 200);
NSRect centeredRectSize = NSMakeSize(50, 100);
NSRect rect = ETCenteredRect(centeredRectSize, ETMakeRect(NSZeroPoint, inRect.size));
</code>
The resulting rect is equal to { 25, 50, 50, 100 }.

The returned rect origin is valid whether or not your coordinate space is flipped. */
static inline NSRect ETCenteredRect(NSSize aSize, NSRect inRect)
{
	float xOffset = aSize.width * 0.5;
	float x = NSMidX(inRect) - xOffset;
	float yOffset = aSize.height  * 0.5;
	float y = NSMidY(inRect) - yOffset;

	return NSMakeRect(x, y, aSize.width, aSize.height);
}

/** Returns a rect with a positive width and height by shifting the origin as 
needed. */
static inline NSRect ETStandardizeRect(NSRect rect)
{
	float minX = NSMinX(rect);
	float minY = NSMinY(rect);
	float width = NSWidth(rect);
	float height = NSHeight(rect);

	if (width < 0)
	{
		minX += width;
		width = -width;
	}
	if (height < 0)
	{
		minY += height;
		height = -height;
	}

	return NSMakeRect(minX, minY, width, height);
}

/** Returns whether rect contains a point expressed in coordinates relative 
to the rect origin. */
static inline BOOL ETPointInsideRect(NSPoint aPoint, NSRect rect)
{
	return ((rect.origin.x + aPoint.x <= rect.size.width) 
		&& (rect.origin.y + aPoint.y <= rect.size.height));
}

/** Returns a new point by summing the x and y coordinates of two points. */
static inline NSPoint ETSumPoint(NSPoint aPoint, NSPoint otherPoint)
{
	return NSMakePoint(aPoint.x + otherPoint.x, aPoint.y + otherPoint.y);
}

/** Returns a new point by summing the point x and y coordinates with the size 
width and height. */
static inline NSPoint ETSumPointAndSize(NSPoint aPoint, NSSize aSize)
{
	return NSMakePoint(aPoint.x + aSize.width, aPoint.y + aSize.height);
}

extern NSRect ETUnionRectWithObjectsAndSelector(NSArray *itemArray, SEL rectSelector);

