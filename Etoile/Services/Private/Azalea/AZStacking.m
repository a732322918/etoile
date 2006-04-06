// Modified by Yen-Ju
/* -*- indent-tabs-mode: nil; tab-width: 4; c-basic-offset: 4; -*-

   stacking.c for the Openbox window manager
   Copyright (c) 2003        Ben Jansens

   This program is free software; you can redistribute it and/or modify
   it under the terms of the GNU General Public License as published by
   the Free Software Foundation; either version 2 of the License, or
   (at your option) any later version.

   This program is distributed in the hope that it will be useful,
   but WITHOUT ANY WARRANTY; without even the implied warranty of
   MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
   GNU General Public License for more details.

   See the COPYING file for a copy of the GNU General Public License.
*/

#import "AZStacking.h"
#import "AZScreen.h"
#import "AZDock.h"
#import "AZGroup.h"
#import "AZClient.h"
#import "openbox.h"
#import "prop.h"

static AZStacking *sharedInstance;

@interface AZStacking (AZPrivate)
- (void) doRestack: (GList *) wins before: (GList *) before;
- (void) doRaise: (GList *) wins;
- (void) doLower: (GList *) wins;
- (GList *)pickWindowsFrom: (AZClient *) top to: (AZClient *) selected raise: (BOOL) raise;
- (GList *)pickGroupWindowsFrom: (AZClient *) top to: (AZClient *) selected raise: (BOOL) raise normal: (BOOL) normal;
@end

@implementation AZStacking

- (void) setList
{
    Window *windows = NULL;
    GList *it;
    unsigned int i = 0;

    /* on shutdown, don't update the properties, so that we can read it back
       in on startup and re-stack the windows as they were before we shut down
    */
    if (ob_state() == OB_STATE_EXITING) return;

    /* create an array of the window ids (from bottom to top,
       reverse order!) */
    if (stacking_list) {
        windows = g_new(Window, g_list_length(stacking_list));
        for (it = g_list_last(stacking_list); it; it = g_list_previous(it)) {
            if (WINDOW_IS_CLIENT(it->data))
                windows[i++] = [((AZClient*)(it->data)) window];
        }
    }

    PROP_SETA32(RootWindow(ob_display, ob_screen),
                net_client_list_stacking, window, (gulong*)windows, i);

    g_free(windows);
}

- (void) raiseWindow: (id <AZWindow>) window group: (BOOL) group
{
    GList *wins;

    if (WINDOW_IS_CLIENT(window)) {
        AZClient *c;
        AZClient *selected;
        selected = (AZClient *)window;
	c = [selected searchTopTransient];
	wins = [self pickWindowsFrom: c to: selected raise: YES];
	wins = g_list_concat(wins, [self pickGroupWindowsFrom: c to: selected raise: YES normal: group]);
    } else {
        wins = g_list_append(NULL, window);
        stacking_list = g_list_remove(stacking_list, window);
    }
    [self doRaise: wins];
    g_list_free(wins);
}

- (void) lowerWindow: (id <AZWindow>) window group: (BOOL) group
{
    GList *wins;

    if (WINDOW_IS_CLIENT(window)) {
        AZClient *c;
        AZClient *selected;
        selected = (AZClient*)window;
	c = [selected searchTopTransient];
	wins = [self pickWindowsFrom: c to: selected raise: NO];
        wins = g_list_concat([self pickGroupWindowsFrom: c to: selected raise: NO normal: group], wins);
    } else {
        wins = g_list_append(NULL, window);
        stacking_list = g_list_remove(stacking_list, window);
    }
    [self doLower: wins];
    g_list_free(wins);
}

- (void) moveWindow: (id <AZWindow>) window belowWindow: (id <AZWindow>) below
{
    GList *wins, *before;

    if ([window windowLayer] != [below windowLayer])
        return;

    wins = g_list_append(NULL, window);
    stacking_list = g_list_remove(stacking_list, window);
    before = g_list_next(g_list_find(stacking_list, below));
    [self doRestack: wins before: before];
    g_list_free(wins);
}

- (void) addWindow: (id <AZWindow>) win
{
    ObStackingLayer l;

    AZScreen *screen = [AZScreen defaultScreen];
    g_assert([screen supportXWindow] != None); /* make sure I dont break this in the
                                             future */

    l = [win windowLayer];

    stacking_list = g_list_append(stacking_list, win);
    [self raiseWindow: win group: NO];
}

- (void) removeWindow: (id <AZWindow>) win
{
  stacking_list = g_list_remove(stacking_list, win);
}

/* Accessories */
- (int) count
{
  return g_list_length(stacking_list);
}

- (id <AZWindow>) windowAtIndex: (int) index
{
  return (id <AZWindow>)g_list_nth_data(stacking_list, index);
}

+ (AZStacking *) stacking
{
  if (sharedInstance == nil)
  {
    sharedInstance = [[AZStacking alloc] init];
  }
  return sharedInstance;
}

@end

@implementation AZStacking (AZPrivate)
- (void) doRestack: (GList *) wins before: (GList *) before;
{
    GList *it, *next;
    Window *win;
    int i;

#ifdef DEBUG
    /* pls only restack stuff in the same layer at a time */
    for (it = wins; it; it = next) {
        next = g_list_next(it);
        if (!next) break;
	g_assert ([((id <AZWindow>)(it->data)) windowLayer] == [((id <AZWindow>)(next->data)) windowLayer]);
    }
    if (before)
	g_assert ([((id <AZWindow>)(it->data)) windowLayer] == [((id <AZWindow>)(before->data)) windowLayer]);
#endif

    win = g_new(Window, g_list_length(wins) + 1);

    if (before == stacking_list)
        win[0] = [[AZScreen defaultScreen] supportXWindow];
    else if (!before)
        win[0] = [(id <AZWindow>)(g_list_last(stacking_list)->data) windowTop];
    else
        win[0] = [(id <AZWindow>)(g_list_previous(before)->data) windowTop];

    for (i = 1, it = wins; it; ++i, it = g_list_next(it)) {
        win[i] = [(id <AZWindow>)(it->data) windowTop];
        g_assert(win[i] != None); /* better not call stacking shit before
                                     setting your top level window value */
        stacking_list = g_list_insert_before(stacking_list, before, it->data);
    }

#ifdef DEBUG
    /* some debug checking of the stacking list's order */
    for (it = stacking_list; ; it = next) {
        next = g_list_next(it);
        if (!next) break;
        g_assert([(id <AZWindow>)(it->data) windowLayer] >= [(id <AZWindow>)(next->data) windowLayer]);
    }
#endif

    XRestackWindows(ob_display, win, i);
    g_free(win);

    [self setList];
}

- (void) doRaise: (GList *) wins
{
#if 1
    NSMutableDictionary *dict = AUTORELEASE([[NSMutableDictionary alloc] init]);
    NSMutableArray *array = nil;
    int i, icount = g_list_length(wins);
    for (i = 0; i < icount; i++) {
      ObStackingLayer l;
      l = [(id <AZWindow>)(g_list_nth_data(wins, i)) windowLayer];

      array = [dict objectForKey: [NSNumber numberWithInt: l]];
      if (array == nil) {
        array = AUTORELEASE([[NSMutableArray alloc] init]);
      }
      [array addObject: [NSValue valueWithPointer: g_list_nth_data(wins, i)]];
      [dict setObject: array forKey: [NSNumber numberWithInt: l]];
    }

    NSArray *allLayers = [dict allKeys];
    NSArray *sorted = [allLayers sortedArrayUsingSelector: @selector(compare:)];

    GList *it = stacking_list;
    GList *layer = NULL;
    int j, jcount = [sorted count];
    int k, kcount = 0;
    for (j = jcount - 1; j > -1; j--) {
      NSArray *a = [dict objectForKey: [sorted objectAtIndex: j]];
      kcount = [a count];
      if (kcount) {
	/* build layer */
	for (k = 0; k < kcount; k++) {
          layer = g_list_append(layer, [[a objectAtIndex: k] pointerValue]);
	}

	for (; it; it = g_list_next(it)) {
          /* look for the top of the layer */
	  if ([(id <AZWindow>)(it->data) windowLayer] <= (ObStackingLayer)[[sorted objectAtIndex: j] intValue])
	  {
	    break;
	  }
	}
	[self doRestack: layer before: it];
	g_list_free(layer);
	layer = NULL;
      }
    }
#else
    GList *it;
    GList *layer[OB_NUM_STACKING_LAYERS] = {NULL};
    int i;

    for (it = wins; it; it = g_list_next(it)) {
        ObStackingLayer l;

        l = window_layer(it->data);
        layer[l] = g_list_append(layer[l], it->data);
    }

    it = stacking_list;
    for (i = OB_NUM_STACKING_LAYERS - 1; i >= 0; --i) {
        if (layer[i]) {
            for (; it; it = g_list_next(it)) {
                /* look for the top of the layer */
                if (window_layer(it->data) <= (ObStackingLayer) i)
                    break;
            }
	    [self doRestack: layer[i] before: it];
            g_list_free(layer[i]);
        }
    }
#endif
}

- (void) doLower: (GList *) wins
{
#if 1
    NSMutableDictionary *dict = AUTORELEASE([[NSMutableDictionary alloc] init]);
    NSMutableArray *array = nil;
    int i, icount = g_list_length(wins);
    for (i = 0; i < icount; i++) {
      ObStackingLayer l;
      l = [(id <AZWindow>)(g_list_nth_data(wins, i)) windowLayer];

      array = [dict objectForKey: [NSNumber numberWithInt: l]];
      if (array == nil) {
        array = AUTORELEASE([[NSMutableArray alloc] init]);
      }
      [array addObject: [NSValue valueWithPointer: g_list_nth_data(wins, i)]];
      [dict setObject: array forKey: [NSNumber numberWithInt: l]];
    }

    NSArray *allLayers = [dict allKeys];
    NSArray *sorted = [allLayers sortedArrayUsingSelector: @selector(compare:)];

    GList *it = stacking_list;
    GList *layer = NULL;
    int j, jcount = [sorted count];
    int k, kcount = 0;
    for (j = jcount - 1; j > -1; j--) {
      NSArray *a = [dict objectForKey: [sorted objectAtIndex: j]];
      kcount = [a count];
      if (kcount) {
	/* build layer */
	for (k = 0; k < kcount; k++) {
          layer = g_list_append(layer, [[a objectAtIndex: k] pointerValue]);
	}

	for (; it; it = g_list_next(it)) {
          /* look for the top of the layer */
	  if ([(id <AZWindow>)(it->data) windowLayer] < (ObStackingLayer)[[sorted objectAtIndex: j] intValue])
	  {
	    break;
	  }
	}
	[self doRestack: layer before: it];
	g_list_free(layer);
	layer = NULL;
      }
    }
#else
    GList *it;
    GList *layer[OB_NUM_STACKING_LAYERS] = {NULL};
    int i;

    for (it = wins; it; it = g_list_next(it)) {
        ObStackingLayer l;

        l = window_layer(it->data);
        layer[l] = g_list_append(layer[l], it->data);
    }

    it = stacking_list;
    for (i = OB_NUM_STACKING_LAYERS - 1; i >= 0; --i) {
        if (layer[i]) {
            for (; it; it = g_list_next(it)) {
                /* look for the top of the next layer down */
                if (window_layer(it->data) < (ObStackingLayer) i)
                    break;
            }
	    [self doRestack: layer[i] before: it];
            g_list_free(layer[i]);
        }
    }
#endif
}

- (GList *)pickWindowsFrom: (AZClient *) top to: (AZClient *) selected 
		     raise: (BOOL) raise
{
    GList *ret = NULL;
    GList *it, *next, *prev;
    int i, n;
    GList *modals = NULL;
    GList *trans = NULL;
    GList *modal_sel = NULL; /* the selected guys if modal */
    GList *trans_sel = NULL; /* the selected guys if not */

    /* remove first so we can't run into ourself */
    if ((it = g_list_find(stacking_list, top)))
        stacking_list = g_list_delete_link(stacking_list, it);
    else
        return NULL;

    i = 0;
    n = [[top transients] count];

    for (it = stacking_list; i < n && it; it = next) {
        prev = g_list_previous(it);
        next = g_list_next(it);


	int index = NSNotFound;

	if (WINDOW_IS_CLIENT(it->data))
	{
	  index = [[top transients] indexOfObject: ((AZClient*)(it->data))];
	}

	if (index != NSNotFound) {
            AZClient *c = [[top transients] objectAtIndex: index];
            BOOL sel_child;

            ++i;

            if (c == selected)
                sel_child = YES;
            else
	    {
		sel_child = ([c searchTransient: selected] != nil);
	    }

            if (![c modal]) {
                if (!sel_child) {
                    trans = g_list_concat(trans,
                         [self pickWindowsFrom: c to: selected raise: raise]);
                } else {
                    trans_sel = g_list_concat(trans_sel,
		   	 [self pickWindowsFrom: c to: selected raise: raise]);
                }
            } else {
                if (!sel_child) {
                    modals = g_list_concat(modals,
                         [self pickWindowsFrom: c to: selected raise: raise]);
                } else {
                    modal_sel = g_list_concat(modal_sel,
                         [self pickWindowsFrom: c to: selected raise: raise]);
                }
            }
            /* if we dont have a prev then start back at the beginning,
               otherwise skip back to the prev's next */
            next = prev ? g_list_next(prev) : stacking_list;
        }
    }

    ret = g_list_concat((raise ? modal_sel : modals),
                        (raise ? modals : modal_sel));

    ret = g_list_concat(ret, (raise ? trans_sel : trans));
    ret = g_list_concat(ret, (raise ? trans : trans_sel));


    /* add itself */
    ret = g_list_append(ret, top);

    return ret;
}

- (GList *)pickGroupWindowsFrom: (AZClient *) top to: (AZClient *) selected
                     raise: (BOOL) raise normal: (BOOL) normal
{
    GList *ret = NULL;
    GList *it = NULL, *next = NULL, *prev = NULL;
    int i, n;

    /* add group members in their stacking order */
    if ((top) && (top != OB_TRAN_GROUP) && ([top group])) {
        i = 0;
	n = [[[top group] members] count]-1;
        for (it = stacking_list; i < n && it; it = next) {
            prev = g_list_previous(it);
            next = g_list_next(it);

	    // This fixes a bug. Probably due to the difference between
	    // glib and GNUstep.
	    if (!WINDOW_IS_CLIENT(it->data))
	    {
              //NSLog(@"Not a client %d", [((id <AZWindow>)(it->data)) windowType]);
	      continue;
	    }

	    int sit = [[top group] indexOfMember: (AZClient*)(it->data)];
	    if (sit != NSNotFound) {
                AZClient *c = nil;
                ObClientType t;

                ++i;
                c = it->data;
                t = [c type];

                if (([c desktop] == [selected desktop] ||
                     [c desktop] == DESKTOP_ALL) &&
                    (t == OB_CLIENT_TYPE_TOOLBAR ||
                     t == OB_CLIENT_TYPE_MENU ||
                     t == OB_CLIENT_TYPE_UTILITY ||
                     (normal && t == OB_CLIENT_TYPE_NORMAL)))
                {
		    AZClient *data = [[top group] memberAtIndex: sit];
                    ret = g_list_concat(ret,
                        [self pickWindowsFrom: data to: selected raise: raise]);
                    /* if we dont have a prev then start back at the beginning,
                       otherwise skip back to the prev's next */
                    next = prev ? g_list_next(prev) : stacking_list;
                }
            }
        }
    }
    return ret;
}
@end
