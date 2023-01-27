#import <Foundation/Foundation.h>
#include "CSWSimplexSolver.h"
#include "AppKit/NSLayoutConstraint.h"

@class NSView;
@class NSLayoutConstraint;

NS_ASSUME_NONNULL_BEGIN

@interface GSAutoLayoutEngine : NSObject

-(instancetype)initWithSolver: (CSWSimplexSolver*)solver;

-(void)addConstraint: (NSLayoutConstraint*)constraint;

-(void)addConstraints: (NSArray*)constraints;

-(void)removeConstraint: (NSLayoutConstraint*)constraint;

-(void)removeConstraints: (NSArray*)constraints;

-(NSRect)alignmentRectForView: (NSView*)view;

-(NSArray*)constraintsForView: (NSView*)view;

-(void)debugSolver;

-(void)invalidateIntrinsicConentSizeForView: (NSView*)view;

- (NSArray*)constraintsAffectingHorizontalOrientationForView:(NSView *)view;

- (NSArray*)constraintsAffectingVerticalOrientationForView:(NSView *)view;

@end

NS_ASSUME_NONNULL_END
