/** <title>ETScrollableAreaItem</title>

	<abstract>ETDecoratorItem subclass which makes content scrollable.</abstract>

	Copyright (C) 2009 Quentin Mathe

	Author:  Quentin Mathe <qmathe@club-internet.fr>
	Date:  March 2009
	License:  Modified BSD  (see COPYING)
 */

#import <Foundation/Foundation.h>
#import <AppKit/AppKit.h>
#import <EtoileUI/ETDecoratorItem.h>
#import <EtoileUI/ETView.h>

/** A decorator which can be used to make content scrollable.

With the AppKit widget backend, the underlying view is an NSScrollView object.

You must not alter the underlying NSScrollView object with -setContentView:.

Non-flipped coordinates are untested with ETScrollableAreaItem i.e. when the 
decorated item returns NO to -isFlipped. */
@interface ETScrollableAreaItem : ETDecoratorItem
{
	@private
	int _oldDecoratedItemAutoresizingMask; /* Autoresizing mask to restore */
	BOOL _ensuresContentFillsVisibleArea;
}

+ (ETScrollableAreaItem *) itemWithScrollView: (NSScrollView *)scrollView;

- (id) initWithScrollView: (NSScrollView *)aScrollView;

- (NSRect) visibleRect;
- (NSRect) visibleContentRect;

- (BOOL) hasVerticalScroller;
- (void) setHasVerticalScroller: (BOOL)scroll;
- (BOOL) hasHorizontalScroller;
- (void) setHasHorizontalScroller: (BOOL)scroll;

- (BOOL) ensuresContentFillsVisibleArea;
- (void) setEnsuresContentFillsVisibleArea: (BOOL)flag;

// TODO: May be nicer to override -contentRect in ETScrollableAreaItem so that 
// the content rect origin reflects the current scroll position.

@end
