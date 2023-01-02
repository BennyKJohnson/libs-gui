#import <Foundation/Foundation.h>
#include "CSWSimplexSolver.h"

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

@end

NS_ASSUME_NONNULL_END
