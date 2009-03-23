/*  <title>ETFlowLayout</title>

	ETFlowLayout.m

	<abstract>A layout class that organize items in an horizontal flow and
	starts a new line each time the content width is filled.</abstract>

	Copyright (C) 2007 Quentin Mathe
 
	Author:  Quentin Mathe <qmathe@club-internet.fr>
	Date:  May 2007
 
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

#import <EtoileFoundation/Macros.h>
#import "ETFlowLayout.h"
#import "ETLayoutItem.h"
#import "ETLayout.h"
#import "ETLayoutLine.h"
#import "NSView+Etoile.h"
#import "ETCompatibility.h"

#define DEFAULT_ITEM_MARGIN 15
#define DEFAULT_MAX_ITEM_SIZE NSMakeSize(256, 256)

@implementation ETFlowLayout

- (id) init
{
	SUPERINIT

	/* Overriden default property values */
	[self setConstrainedItemSize: DEFAULT_MAX_ITEM_SIZE];
	[self setItemSizeConstraintStyle: ETSizeConstraintStyleVerticalHorizontal];
	[self setItemMargin: DEFAULT_ITEM_MARGIN];
	
	_layoutConstraint = ETSizeConstraintStyleHorizontal;

	return self;
}

/** Runs the layout computation which assigns a location in the layout context
to the items, which are expected to be already broken into lines in layoutModel. */
- (void) computeLayoutItemLocationsForLayoutModel: (NSArray *)layoutModel
{
	float itemMargin = [self itemMargin];
	NSPoint itemLocation = NSMakePoint(itemMargin, itemMargin);
	float newLayoutHeight = 0;
	BOOL isFlipped = [[self layoutContext] isFlipped];

	if (isFlipped == NO)
	{
		ETLog(@"WARNING: Flow layout doesn't handle non-flipped coordinates inside a scroll view");
		itemLocation = NSMakePoint(itemMargin, [self layoutSize].height - itemMargin);
	}

	FOREACH(layoutModel, line, ETLayoutLine *)
	{
    /*
         A +---------------------------------------
           |          ----------------
           |----------|              |    Layout
           | Layouted |   Layouted   |    Line
           |  Item 1  |   Item 2     |
         --+--------------------------------------- <-- here is the baseline
           B
       
       In the layout context coordinates we have:   
       baseLineLocation.x = A.x and baseLineLocation.y = A.y - B.y
       
     */

		[line setBaseLineLocation: itemLocation];
    
		FOREACH([line items], item, ETLayoutItem *)
		{
			[item setX: itemLocation.x];
			itemLocation.x += [item width] + itemMargin;
		}

		// TODO: To avoid computing item locations when they are outside of the
		// frame, think to add an exit condition here.
    
		/* Before computing the following items location in 'x' on the next line, 
		   we have to reset the 'x' accumulator and take in account the end of 
		   the current line, by substracting to 'y' the last layout line height. */
		if (isFlipped)
		{
			[line setBaseLineLocation: 
				NSMakePoint([line baseLineLocation].x, itemLocation.y)];
			itemLocation.y = [line baseLineLocation].y + [line height] + itemMargin;
		}
		else
		{
			[line setBaseLineLocation: 
				NSMakePoint([line baseLineLocation].x, itemLocation.y - [line height])];
			itemLocation.y = [line baseLineLocation].y + itemMargin;		
		}
		itemLocation.x = itemMargin;

		/* Increase height of the content size. Used to adjust the document 
		   view size in scroll view */
		newLayoutHeight += [line height] + itemMargin;

		ETDebugLog(@"Item locations computed by layout line :%@", line);
	}

	[self setLayoutSize: NSMakeSize([self layoutSize].width, newLayoutHeight)];
}

/** Breaks the items into lines and returns the resulting array as a layout model. */
- (NSArray *) layoutModelForLayoutItems: (NSArray *)items
{
	NSMutableArray *unlayoutedItems = 
		[NSMutableArray arrayWithArray: items];
	ETLayoutLine *line = nil;
	NSMutableArray *layoutModel = [NSMutableArray array];

	while ([unlayoutedItems count] > 0)
	{
		line = [self layoutLineForLayoutItems: unlayoutedItems];
		
		if ([[line items] count] > 0)
		{
			[layoutModel addObject: line];    
				
			/* In unlayoutedItems, remove the items which have just been 
			   layouted on the previous line. */
			[unlayoutedItems removeObjectsInArray: [line items]];
		}
		else
		{
			ETLog(@"Not enough space to layout all the items. Items remaining unlayouted: %@", unlayoutedItems);
			break;
		}
	}

	return layoutModel;
}

/** Returns a line filled with items to layout.

Fills the layout line by iterating over the items until the total width extends 
beyond the right boundary. At that point, the new line is returned whether or 
not every items have been inserted into it.

When items is empty, returns an empty layout line. */
- (ETLayoutLine *) layoutLineForLayoutItems: (NSArray *)items
{
	NSMutableArray *layoutedItems = [NSMutableArray array];
	ETLayoutLine *line = nil;
	float widthAccumulator = 0;
	float itemMargin = [self itemMargin];

	FOREACH(items, itemToLayout, ETLayoutItem *)
	{
		widthAccumulator += itemMargin + [itemToLayout width];
		
		if ([self layoutSizeConstraintStyle] != ETSizeConstraintStyleHorizontal
		 || widthAccumulator < [self layoutSize].width)
		{
			[layoutedItems addObject: itemToLayout];
		}
		else
		{
			break;
		}
	}

	// NOTE: Not really useful for now because we don't support filling the 
	// layout horizontally, only vertical filling is in place.
	// We only touch the layout size height in -computeItemLocationsForLayoutModel:
	if ([self isContentSizeLayout] && [self layoutSize].width < widthAccumulator)
		[self setLayoutSize: NSMakeSize(widthAccumulator, [self layoutSize].height)];

	if ([layoutedItems count] == 0)
		return nil;

	line = [ETLayoutLine layoutLineWithLayoutItems: layoutedItems];
	[line setVerticallyOriented: NO];

	return line;
}

/** Lets you control the constraint applied on the layout when 
-isContentSizeLayout returns YES. The most common case is when the layout is set 
on a layout item embbeded in a scroll view. 

By passing ETSizeConstraintStyleVertical, the layout will try to fill the 
limited height (provided by -layoutSize) with as many lines of equal width as 
possible. In this case, layout width and line width are stretched.

By passing ETSizeConstraintStyleHorizontal, the layout will try to fill the 
unlimited height with as many lines of equally limited width (returned
by -layoutSize) as needed. In this case, only layout height is stretched. 

ETSizeConstraintStyleNone and ETSizeConstraintStyleVerticalHorizontal are not 
supported. If you use them, the receiver resets ETSizeConstraintStyleHorizontal 
default value. */
- (void) setLayoutSizeConstraintStyle: (ETSizeConstraintStyle)constraint
{
	if (constraint == ETSizeConstraintStyleHorizontal 
	 || constraint == ETSizeConstraintStyleVertical)
	{ 
		_layoutConstraint = constraint;
	}
	else
	{
		_layoutConstraint = ETSizeConstraintStyleHorizontal;
	}
}

/** Returns the constraint applied on the layout which are only valid when 
-isContentSizeLayout returns YES. 

Default value is ETSizeConstraintStyleHorizontal. */
- (ETSizeConstraintStyle) layoutSizeConstraintStyle
{
	return _layoutConstraint;
}

- (BOOL) usesGrid
{
	return _grid;
}

- (void) setUsesGrid: (BOOL)constraint
{
	_grid = constraint;
}

@end