#import "GSAutoLayoutEngine.h"
#include "AppKit/NSLayoutConstraint.h"
#include "CSWConstraint.h"
#include "CSWSimplexSolverSolution.h"

enum {
    GSLayoutViewAttributeBaselineOffsetFromBottom = 1,
    GSLayoutViewAttributeFirstBaselineOffsetFromTop,
    GSLayoutViewAttributeIntrinsicWidth,
    GSLayoutViewAttributeInstrinctHeight,
};
typedef NSUInteger GSLayoutViewAttribute;

enum {
    GSLayoutAttributeNotAnAttribute = 0,
    GSLayoutAttributeLeft = 1,
    GSLayoutAttributeRight,
    GSLayoutAttributeTop,
    GSLayoutAttributeBottom,
    GSLayoutAttributeLeading,
    GSLayoutAttributeTrailing,
    GSLayoutAttributeWidth,
    GSLayoutAttributeHeight,
    GSLayoutAttributeCenterX,
    GSLayoutAttributeCenterY,
    GSLayoutAttributeLastBaseline,
    GSLayoutAttributeBaseline = GSLayoutAttributeLastBaseline,
    GSLayoutAttributeFirstBaseline,
    GSLayoutAttributeMinX = 32,
    GSLayoutAttributeMinY = 33,
    GSLayoutAttributeMaxX = 36,
    GSLayoutAttributeMaxY = 37
};
typedef NSUInteger GSLayoutAttribute;

@implementation GSAutoLayoutEngine
{
    CSWSimplexSolver *solver;
    NSMapTable *variablesByKey;
    NSMutableArray *solverConstraints;
    NSMapTable *constraintsByAutoLayoutConstaintHash;
    NSMutableArray *trackedViews;
    NSMutableDictionary *viewIndexByViewHash;
    NSMutableDictionary *viewAlignmentRectByViewIndex;
    NSMutableDictionary *constraintsByViewIndex;
    NSMapTable *internalConstraintsByViewIndex;
    NSMapTable *supportingConstraintsByConstraint;
    int viewCounter;
}

-(instancetype)initWithSolver: (CSWSimplexSolver*)simplexSolver
{
    if (self = [super init]) {
        viewCounter = 0;
        solver = simplexSolver;
  
        // Stores a solver variable against an identifier so it can be looked up later and not recreated
        variablesByKey = [NSMapTable strongToStrongObjectsMapTable];
        [variablesByKey retain];

        constraintsByAutoLayoutConstaintHash = [NSMapTable strongToStrongObjectsMapTable];
        [constraintsByAutoLayoutConstaintHash retain];

        solverConstraints = [NSMutableArray array];
        [solverConstraints retain];
        
        trackedViews = [NSMutableArray array];
        [trackedViews retain];

        supportingConstraintsByConstraint = [NSMapTable strongToStrongObjectsMapTable];
        [supportingConstraintsByConstraint retain];

        viewAlignmentRectByViewIndex = [NSMutableDictionary dictionary];
        [viewAlignmentRectByViewIndex retain];

        viewIndexByViewHash = [NSMutableDictionary dictionary];
        [viewIndexByViewHash retain];

        constraintsByViewIndex = [NSMutableDictionary dictionary];
        [constraintsByViewIndex retain];
        
        internalConstraintsByViewIndex = [NSMapTable strongToStrongObjectsMapTable];
        [internalConstraintsByViewIndex retain];
    }
    return self;
}

- (instancetype)init {
    CSWSimplexSolver *solver = [[CSWSimplexSolver alloc] init];
    return [self initWithSolver: solver];
}

-(void)resolveVariableForView: (NSView*)view attribute: (GSLayoutViewAttribute)attribute
{
    CSWVariable *editVariable = [self getExistingVariableForView:view withVariable:attribute];
    CGFloat value = [self valueForView: view attribute: attribute];

    [solver suggestEditVariable:editVariable equals:value];    
    [self updateAlignmentRectsForTrackedViews];
}

-(CGFloat)valueForView: (NSView*)view attribute: (GSLayoutViewAttribute)attribute
{
    switch (attribute) {
        case GSLayoutViewAttributeBaselineOffsetFromBottom:
            return [view baselineOffsetFromBottom];
        case GSLayoutViewAttributeFirstBaselineOffsetFromTop:
            return [view firstBaselineOffsetFromTop];
        case GSLayoutViewAttributeIntrinsicWidth:
            return [view intrinsicContentSize].width;
        case GSLayoutViewAttributeInstrinctHeight:
            return [view intrinsicContentSize].height;
        default:
            [[NSException exceptionWithName:@"Not handled"
                reason:@"GSLayoutAttribute not handled"
                userInfo:nil] raise];
            return 0;
    }
}

-(NSRect)_solverAlignmentRectForView:(NSView *)view solution: (CSWSimplexSolverSolution*)solution
{
    CSWVariable *minX = [self getExistingVariableForView:view withAttribute:GSLayoutAttributeMinX];
    CSWVariable *minY = [self getExistingVariableForView:view withAttribute:GSLayoutAttributeMinY];
    CSWVariable *width = [self getExistingVariableForView:view withAttribute:GSLayoutAttributeWidth];
    CSWVariable *height = [self getExistingVariableForView:view withAttribute:GSLayoutAttributeHeight];

    return NSMakeRect(
        [[solution resultForVariable: minX] floatValue],
        [[solution resultForVariable: minY] floatValue],
        [[solution resultForVariable: width] floatValue],
        [[solution resultForVariable: height] floatValue]
    );
}

-(BOOL)_solverCanSolveAlignmentRectForView: (NSView*)view solution: (CSWSimplexSolverSolution*)solution {
    CSWVariable *minX = [self getExistingVariableForView:view withAttribute:GSLayoutAttributeMinX];
    if (!minX) {
        return NO;
    }
    CSWVariable *minY = [self getExistingVariableForView:view withAttribute:GSLayoutAttributeMinY];
    if (!minY) {
        return NO;
    }
    CSWVariable *width = [self getExistingVariableForView:view withAttribute:GSLayoutAttributeWidth];
    if (!width || ![[solution resultForVariable: width] floatValue]) {
        return NO;
    }
    CSWVariable *height = [self getExistingVariableForView:view withAttribute:GSLayoutAttributeHeight];
    if (!height || ![[solution resultForVariable: height] floatValue]) {
        return NO;
    }
    
    return YES;
}

-(BOOL)isValidNSRect: (NSRect)rect
{
    return rect.origin.x >= 0 && rect.origin.y >= 0;
}

-(void)updateAlignmentRectsForTrackedViews
{
    CSWSimplexSolverSolution *solution = [solver solve];
    NSMutableArray *viewsWithChanges = [NSMutableArray array];
    for (NSView *view in trackedViews) {
        NSNumber *viewIndex = [self indexForView:view];
        if ([self _solverCanSolveAlignmentRectForView: view solution: solution]) {
            NSRect existingAlignmentRect = [self currentAlignmentRectForViewAtIndex:viewIndex];
            BOOL isExistingAlignmentRect = [self isValidNSRect: existingAlignmentRect];
            NSRect solverAlignmentRect = [self _solverAlignmentRectForView:view solution: solution];
            [self recordAlignmentRect:solverAlignmentRect forViewIndex:viewIndex];
            
            if (isExistingAlignmentRect == NO || !NSEqualRects(solverAlignmentRect, existingAlignmentRect)) {
                [viewsWithChanges addObject:view];
            }
        }
    }
    
    [self notifyViewsOfAlignmentRectChange:viewsWithChanges];
}

-(void)notifyViewsOfAlignmentRectChange: (NSArray*)viewsWithChanges
{
    for (NSView *view in viewsWithChanges) {
        [view layoutEngineDidChangeAlignmentRect];
    }
}

-(BOOL)hasExistingAlignmentRectForView: (NSView*)view
{
    NSNumber *viewIndex = [viewIndexByViewHash objectForKey:[NSNumber numberWithUnsignedInteger:[view hash]]];
    NSValue *existingRectValue = [viewAlignmentRectByViewIndex objectForKey:viewIndex];
    return existingRectValue != nil;
}

-(void)recordAlignmentRect: (NSRect)alignmentRect forViewIndex: (NSNumber*)viewIndex
{
    NSValue *newRectValue = [NSValue valueWithRect:alignmentRect];
    [viewAlignmentRectByViewIndex setObject:newRectValue forKey:viewIndex];
}

-(NSRect)currentAlignmentRectForViewAtIndex: (NSNumber*)viewIndex
{
    NSValue *existingRectValue = [viewAlignmentRectByViewIndex objectForKey:viewIndex];
    if (existingRectValue == nil) {
        return NSMakeRect(-1, -1, -1, -1);
    }
    NSRect existingAlignmentRect;
    [existingRectValue getValue: &existingAlignmentRect];
    return existingAlignmentRect;
}

-(NSRect)alignmentRectForView: (NSView*)view {
    NSNumber *viewIndex = [self indexForView:view];
    
    return [self currentAlignmentRectForViewAtIndex:viewIndex];
}

-(NSString*)getIdentifierForView:(NSView*)view
{
    NSUInteger viewIndex;
    NSNumber *existingViewIndex = [self indexForView:view];
    if (existingViewIndex) {
        viewIndex = [existingViewIndex unsignedIntegerValue];
    } else {
        viewIndex = [self registerView:view];
    }
    
    return [NSString stringWithFormat: @"view%ld", (long)viewIndex];
}

-(NSNumber*)indexForView: (NSView*)view
{
    return [viewIndexByViewHash objectForKey:[NSNumber numberWithUnsignedInteger:[view hash]]];
}

-(NSString*)getViewIndentifierForIndex: (NSUInteger)viewIndex
{
    return [NSString stringWithFormat: @"view%ld", (long)viewIndex];
}

-(NSInteger)registerView: (NSView*)view {
    NSUInteger viewIndex = [trackedViews count];
    [trackedViews addObject:view];
    [viewIndexByViewHash setObject:[NSNumber numberWithUnsignedInteger:viewIndex] forKey: [NSNumber numberWithUnsignedInteger:[view hash]]];
     
    return viewIndex;
}

-(void)addConstraint:(NSLayoutConstraint*)constraint
{
    CSWConstraint *solverConstraint = [self solverConstraintForConstraint: constraint];
    [constraintsByAutoLayoutConstaintHash setObject: solverConstraint forKey: constraint];

    [self addSupportingInternalConstraintsToView:[constraint firstItem] forAttribute:[constraint firstAttribute] constraint: solverConstraint];
    
    if ([constraint secondItem]) {
        [self addSupportingInternalConstraintsToView:[constraint secondItem] forAttribute:[constraint secondAttribute] constraint: solverConstraint];
    }
    
    [self addObserverToConstraint:constraint];
    
    @try {
        [self addSolverConstraint:solverConstraint];
        [self updateAlignmentRectsForTrackedViews];
    } @catch (NSException *exception) {
        NSLog(@"Unable to simultaneously satisfy constraints\nWill attempt to recover by breaking constraint\n%@", constraint);
    }

    [self addConstraintAgainstViewConstraintsArray: constraint];
}

-(void) addConstraintAgainstViewConstraintsArray: (NSLayoutConstraint*)constraint
{
    NSNumber *firstItemViewIndex = [self indexForView: [constraint firstItem]];
    NSMutableArray *constraintsForView = constraintsByViewIndex[firstItemViewIndex];
    if (!constraintsForView) {
        constraintsForView = [NSMutableArray array];
        constraintsByViewIndex[firstItemViewIndex] = constraintsForView;
    }
    [constraintsForView addObject: constraint];

    if ([constraint secondItem] != nil) {
        NSNumber *secondItemViewIndex = [self indexForView: [constraint secondItem]];
        if (constraintsByViewIndex[secondItemViewIndex] == nil) {
            constraintsByViewIndex[secondItemViewIndex] = [NSMutableArray array];
        }
        [constraintsByViewIndex[secondItemViewIndex] addObject: constraint];
    }
}

-(BOOL)hasAddedWidthAndHeightConstraintsToView: (NSView*)view
{
    NSArray *added = [internalConstraintsByViewIndex objectForKey: view];
    return added != nil;
}

-(void)addSupportingInternalConstraintsToView: (NSView*)view forAttribute: (NSLayoutAttribute)attribute constraint: (CSWConstraint*)constraint
{
    if (![self hasAddedWidthAndHeightConstraintsToView: view]) {
        [self addInternalWidthConstraintForView: view];
        [self addInternalHeightConstraintForView: view];
        [self addIntrinsicContentSizeConstraintsToView: view];
    }

    switch (attribute) {
        case NSLayoutAttributeTrailing:
            [self addInternalTrailingConstraintForView: view constraint: constraint];
            break;
        case NSLayoutAttributeLeading:
            [self addInternalLeadingConstraintForView: view constraint: constraint];
            break;
        case NSLayoutAttributeLeft:
            [self addInternalLeftConstraintForView: view constraint: constraint];
            break;
        case NSLayoutAttributeRight:
            [self addInternalRightConstraintForView: view constraint: constraint];
            break;
        case NSLayoutAttributeTop:
            [self addInternalTopConstraintForView: view constraint: constraint];
            break;
        case NSLayoutAttributeBottom:
            [self addInternalBottomConstraintForView: view constraint: constraint];
            break;
        case NSLayoutAttributeCenterX:
            [self addInternalCenterXConstraintsForView:view constraint: constraint];
            break;
        case NSLayoutAttributeCenterY:
            [self addInternalCenterYConstraintsForView:view constraint: constraint];
            break;
        case NSLayoutAttributeBaseline:
            [self addInternalBaselineConstraintsForView:view constraint: constraint];
            break;
        case NSLayoutAttributeFirstBaseline:
            [self addInternalFirstBaselineConstraintsForView: view constraint: constraint];
        default:
            break;
    }
}

-(void)addInternalWidthConstraintForView: (NSView*)view
{
    CSWVariable *widthConstraintVariable = [self variableForView: view andAttribute: GSLayoutAttributeWidth];
    CSWVariable *minX = [self variableForView:view andAttribute:GSLayoutAttributeMinX];
    CSWVariable *maxX = [self variableForView:view andAttribute:GSLayoutAttributeMaxX];

    CSWLinearExpression *maxXMinusMinX = [[CSWLinearExpression alloc] initWithVariable: maxX];
    [maxXMinusMinX addVariable: minX coefficient: -1];
    CSWConstraint *widthRelationshipToMaxXAndMinXConstraint = [CSWConstraint constraintWithLeftVariable: widthConstraintVariable operator: CSWConstraintOperatorEqual rightExpression: maxXMinusMinX];
    
    [self addInternalSolverConstraint:widthRelationshipToMaxXAndMinXConstraint forView: view];
}

-(void)addInternalHeightConstraintForView: (NSView*)view
{
    CSWVariable *heightConstraintVariable = [self variableForView: view andAttribute: GSLayoutAttributeHeight];
    CSWVariable *minY = [self variableForView:view andAttribute:GSLayoutAttributeMinY];
    CSWVariable *maxY = [self variableForView:view andAttribute:GSLayoutAttributeMaxY];

    CSWLinearExpression *maxYMinusMinY = [[CSWLinearExpression alloc] initWithVariable: maxY];
    [maxYMinusMinY addVariable: minY coefficient: -1];
    CSWConstraint *heightConstraint = [CSWConstraint constraintWithLeftVariable: heightConstraintVariable operator:CSWConstraintOperatorEqual rightExpression: maxYMinusMinY];
    
    [self addInternalSolverConstraint:heightConstraint forView: view];
}

-(void)addInternalSolverConstraint: (CSWConstraint*)constraint forView: (NSView*)view
{
    [self addSolverConstraint:constraint];

    NSArray *internalViewConstraints = [internalConstraintsByViewIndex objectForKey: view];
    if (internalViewConstraints == nil) {
        [internalConstraintsByViewIndex setObject: [NSMutableArray array] forKey: view];
    }
    [[internalConstraintsByViewIndex objectForKey: view] addObject: constraint];
}

-(void)addInternalLeadingConstraintForView: (NSView*)view constraint: (CSWConstraint*)constraint
{
    CSWVariable *minX = [self variableForView:view andAttribute:GSLayoutAttributeMinX];
    CSWVariable *leadingVariable = [self variableForView:view andAttribute:GSLayoutAttributeLeading];
    CSWConstraint *minXLeadingRelationshipConstraint = [CSWConstraint constraintWithLeftVariable: minX operator:CSWConstraintOperatorEqual rightVariable: leadingVariable];
    [self addSupportingSolverConstraint:minXLeadingRelationshipConstraint forSolverConstraint: constraint];
}

-(void)addInternalTrailingConstraintForView: (NSView*)view constraint: (CSWConstraint*)constraint
{
    CSWVariable * trailingVariable = [self variableForView:view andAttribute:GSLayoutAttributeTrailing];
    CSWVariable *maxX = [self variableForView:view andAttribute:GSLayoutAttributeMaxX];
    CSWConstraint *maxXTrailingRelationshipConstraint = [CSWConstraint constraintWithLeftVariable: maxX operator:CSWConstraintOperatorEqual rightVariable: trailingVariable];
    [self addSupportingSolverConstraint: maxXTrailingRelationshipConstraint forSolverConstraint: constraint];
}

-(void)addInternalLeftConstraintForView: (NSView*)view constraint: (CSWConstraint*)constraint
{
    CSWVariable *minX = [self variableForView:view andAttribute:GSLayoutAttributeMinX];
    CSWVariable *leftVariable = [self variableForView:view andAttribute:GSLayoutAttributeLeft];
    CSWConstraint *minXLeadingRelationshipConstraint = [CSWConstraint constraintWithLeftVariable: minX operator:CSWConstraintOperatorEqual rightVariable: leftVariable];
    [self addSupportingSolverConstraint:minXLeadingRelationshipConstraint forSolverConstraint: constraint];
}

-(void)addInternalRightConstraintForView: (NSView*)view constraint: (CSWConstraint*)constraint
{
    CSWVariable *maxX = [self variableForView:view andAttribute:GSLayoutAttributeMaxX];
    CSWVariable *rightVariable = [self variableForView:view andAttribute:GSLayoutAttributeRight];
    CSWConstraint *maxXRightRelationshipConstraint = [CSWConstraint constraintWithLeftVariable: maxX operator:CSWConstraintOperatorEqual rightVariable: rightVariable];
    [self addSupportingSolverConstraint: maxXRightRelationshipConstraint forSolverConstraint: constraint];
}

-(void)addInternalBottomConstraintForView: (NSView*)view constraint: (CSWConstraint*)constraint
{
    CSWVariable *minY = [self variableForView:view andAttribute:GSLayoutAttributeMinY];
    CSWVariable *bottomVariable = [self variableForView:view andAttribute:GSLayoutAttributeBottom];
    CSWConstraint *minYBottomRelationshipConstraint = [CSWConstraint constraintWithLeftVariable: minY operator:CSWConstraintOperatorEqual rightVariable: bottomVariable];
    [self addSupportingSolverConstraint:minYBottomRelationshipConstraint forSolverConstraint: constraint];
}

-(void)addInternalTopConstraintForView: (NSView*)view constraint: (CSWConstraint*)constraint
{
    CSWVariable *maxY = [self variableForView:view andAttribute:GSLayoutAttributeMaxY];
    CSWVariable *topVariable = [self variableForView:view andAttribute:GSLayoutAttributeTop];
    CSWConstraint *maxYTopRelationshipConstraint = [CSWConstraint constraintWithLeftVariable: maxY operator:CSWConstraintOperatorEqual rightVariable: topVariable];
    [self addSupportingSolverConstraint:maxYTopRelationshipConstraint forSolverConstraint: constraint];
}

-(void)addInternalCenterXConstraintsForView: (NSView*)view constraint: (CSWConstraint*)constraint
{
    CSWVariable *centerXVariable = [self variableForView:view andAttribute:GSLayoutAttributeCenterX];
    CSWVariable *width = [self variableForView:view andAttribute:GSLayoutAttributeWidth];
    CSWVariable *minX = [self variableForView:view andAttribute:GSLayoutAttributeMinX];

    CSWLinearExpression *exp = [[CSWLinearExpression alloc] initWithVariable: minX];
    [exp addVariable: width coefficient: 0.5];
    CSWConstraint *centerXConstraint = [CSWConstraint constraintWithLeftVariable: centerXVariable operator: CSWConstraintOperatorEqual rightExpression: exp];
    
    [self addSupportingSolverConstraint:centerXConstraint forSolverConstraint: constraint];
}

-(void)addInternalCenterYConstraintsForView: (NSView*)view constraint: (CSWConstraint*)constraint
{
    CSWVariable *centerYVariable = [self variableForView:view andAttribute:GSLayoutAttributeCenterY];
    CSWVariable *height = [self variableForView: view andAttribute:GSLayoutAttributeHeight];
    CSWVariable *minY = [self variableForView:view andAttribute:GSLayoutAttributeMinY];
    
    CSWLinearExpression *exp = [[CSWLinearExpression alloc] initWithVariable: minY];
    [exp addVariable: height coefficient: 0.5];
    CSWConstraint *centerYConstraint = [CSWConstraint constraintWithLeftVariable: centerYVariable operator: CSWConstraintOperatorEqual rightExpression: exp];
    [self addSupportingSolverConstraint:centerYConstraint forSolverConstraint: constraint];
}

-(void)addInternalFirstBaselineConstraintsForView: (NSView*)view constraint: (CSWConstraint*)constraint
{
    CSWVariable *firstBaselineVariable = [self variableForView:view andAttribute:GSLayoutAttributeFirstBaseline];
    CSWVariable *maxY = [self variableForView:view andAttribute:GSLayoutAttributeMaxY];
    CSWVariable *firstBaselineOffsetVariable = [self variableForView: view andViewAttribute:GSLayoutViewAttributeFirstBaselineOffsetFromTop];
    
    CSWLinearExpression *exp = [[CSWLinearExpression alloc] initWithVariable: maxY];
    [exp addVariable: firstBaselineOffsetVariable coefficient: -1];
    CSWConstraint *firstBaselineConstraint = [CSWConstraint constraintWithLeftVariable: firstBaselineVariable operator: CSWConstraintOperatorEqual rightExpression: exp];

    [self addSupportingConstraintForLayoutViewAttribute:GSLayoutViewAttributeFirstBaselineOffsetFromTop view:view constraint: constraint];
    [self addSupportingSolverConstraint:firstBaselineConstraint forSolverConstraint: constraint];
}

-(void)addInternalBaselineConstraintsForView: (NSView*)view constraint: (CSWConstraint*)constraint
{
    CSWVariable *baselineVariable = [self variableForView:view andAttribute:GSLayoutAttributeBaseline];
    CSWVariable *minY = [self variableForView:view andAttribute:GSLayoutAttributeMinY];
    CSWVariable *baselineOffsetVariable = [self variableForView: view andViewAttribute:GSLayoutViewAttributeBaselineOffsetFromBottom];

    [self addSupportingConstraintForLayoutViewAttribute:GSLayoutViewAttributeBaselineOffsetFromBottom view:view constraint: constraint];
    CSWLinearExpression *exp = [[CSWLinearExpression alloc] initWithVariable: minY];
    [exp addVariable: baselineOffsetVariable];
    CSWConstraint *baselineConstraint = [CSWConstraint constraintWithLeftVariable: baselineVariable operator: CSWConstraintOperatorEqual rightExpression: exp];

    [self addSupportingSolverConstraint:baselineConstraint forSolverConstraint: constraint];
}

-(void)addIntrinsicContentSizeConstraintsToView: (NSView*)view
{
    NSSize intrinsicContentSize = [view intrinsicContentSize];
    if (intrinsicContentSize.width != NSViewNoIntrinsicMetric) {
        [self addSupportingInstrictSizeConstraintsToView:view orientation:NSLayoutConstraintOrientationHorizontal instrinctSizeAttribute:GSLayoutViewAttributeIntrinsicWidth dimensionAttribute:GSLayoutAttributeWidth];
    }
    if (intrinsicContentSize.height != NSViewNoIntrinsicMetric) {
        [self addSupportingInstrictSizeConstraintsToView:view orientation:NSLayoutConstraintOrientationVertical
            instrinctSizeAttribute: GSLayoutViewAttributeInstrinctHeight
            dimensionAttribute:GSLayoutAttributeHeight];
    }
}

-(void)addSupportingInstrictSizeConstraintsToView: (NSView*)view orientation: (NSLayoutConstraintOrientation)orientation instrinctSizeAttribute: (GSLayoutViewAttribute)instrinctSizeAttribute dimensionAttribute: (GSLayoutAttribute)dimensionAttribute {
    CSWVariable *instrinctContentDimension = [self variableForView:view andViewAttribute:instrinctSizeAttribute];
    CSWVariable *dimensionVariable = [self variableForView:view andAttribute:dimensionAttribute];

    CSWVariable *instrinctSizeVariable = [self getExistingVariableForView:view withVariable:instrinctSizeAttribute];
    CSWConstraint *instrinctSizeConstraint = [CSWConstraint editConstraintWithVariable:instrinctSizeVariable];
    [self addInternalSolverConstraint:instrinctSizeConstraint forView: view];
    [self resolveVariableForView: view attribute: instrinctSizeAttribute];

    double huggingPriority = [view contentHuggingPriorityForOrientation:orientation];
    CSWConstraint *huggingConstraint = [CSWConstraint constraintWithLeftVariable: dimensionVariable operator: CSWConstraintOperatorLessThanOrEqual rightVariable: instrinctContentDimension];
    huggingConstraint.strength = [[[CSWStrength alloc] initWithName:nil strength:huggingPriority] autorelease];

    [self addInternalSolverConstraint:huggingConstraint forView: view];
    
    double compressionPriority = [view contentCompressionResistancePriorityForOrientation:orientation];
    CSWConstraint *compressionConstraint = [CSWConstraint constraintWithLeftVariable: dimensionVariable operator: CSWConstraintOperationGreaterThanOrEqual rightVariable: instrinctContentDimension];
    compressionConstraint.strength = [[[CSWStrength alloc] initWithName:nil strength:compressionPriority] autorelease];

    [self addInternalSolverConstraint:compressionConstraint forView: view];
}

-(void)addSupportingConstraintForLayoutViewAttribute: (GSLayoutViewAttribute)attribute view: (NSView*)view constraint: (CSWConstraint*)constraint
{
    CSWVariable *variable = [self getExistingVariableForView:view withVariable:attribute];
    CSWConstraint *editConstraint = [CSWConstraint editConstraintWithVariable:variable];
    [self addSupportingSolverConstraint: editConstraint forSolverConstraint: constraint];
    [self resolveVariableForView: view attribute: attribute];
}

-(void)addObserverToConstraint: (NSLayoutConstraint*)constranit
{
    [constranit addObserver:self forKeyPath:@"constant" options:NSKeyValueObservingOptionNew context:nil];
}

- (void)observeValueForKeyPath:(NSString *)keyPath ofObject:(id)object change:(NSDictionary *)change context:(void *)context {
    
    if ([object isKindOfClass:[NSLayoutConstraint class]]) {
        NSLayoutConstraint *constraint = (NSLayoutConstraint *)object;
        [self updateConstraint:constraint];
    }
}

-(void)updateConstraint: (NSLayoutConstraint*)constraint
{
    CSWConstraint *kConstraint = [self getExistingConstraintForAutolayoutConstraint:constraint];
    [self removeSolverConstraint:kConstraint];
    
    CSWConstraint *newKConstraint = [self solverConstraintForConstraint:constraint];
    [constraintsByAutoLayoutConstaintHash setObject: newKConstraint forKey: constraint];
    [self addSolverConstraint:newKConstraint];

    [self updateAlignmentRectsForTrackedViews];
}

-(void)addConstraints: (NSArray*)constraints
{
    for (id constraint in constraints) {
        [self addConstraint:constraint];
    }
}

-(CSWVariable*)variableForView:(NSView*)view andAttribute: (GSLayoutAttribute)attribute
{
    CSWVariable *existingVariable = [self getExistingVariableForView:view withAttribute:(GSLayoutAttribute)attribute];
    if (existingVariable != nil) {
        return existingVariable;
    } else {
        return [self createVariableForView: view withAttribute: attribute];
    }
}

-(CSWVariable*)variableForView: (NSView*)view andViewAttribute: (GSLayoutViewAttribute)attribute
{
    CSWVariable *existingVariable = [self getExistingVariableForView:view withVariable:attribute];
    if (existingVariable != nil) {
        return existingVariable;
    } else {
        return [self createVariableForView:view attribute:attribute];
    }
}

// Variable Management

-(CSWVariable*)getExistingVariableForView:(NSView*)view withAttribute: (GSLayoutAttribute)attribute
{
    NSString *variableIdentifier = [self getVariableIdentifierForView: view withAttribute: (GSLayoutAttribute)attribute];
    return [self varibleWithName:variableIdentifier];
}

-(CSWVariable*)getExistingVariableForView: (NSView*)view withVariable: (GSLayoutViewAttribute)attribute
{
    NSString *variableIdentifier = [self getDynamicVariableIdentifierForView:view withViewAttribute:attribute];
    return [self varibleWithName:variableIdentifier];
}

-(CSWVariable*) varibleWithName:(NSString*)variableName
{
    return [variablesByKey objectForKey: variableName];
}

-(CSWVariable*)createVariableForView:(NSView*)view withAttribute: (GSLayoutAttribute)attribute
{
    NSString *variableIdentifier = [self getVariableIdentifierForView: view withAttribute: attribute];
    
    return [self createVariableWithName:variableIdentifier];
}

-(CSWVariable*)createVariableForView:(NSView*)view attribute: (GSLayoutViewAttribute)attribute
{
    NSString *variableIdentifier = [self getDynamicVariableIdentifierForView:view withViewAttribute:attribute];
    CSWVariable *variable = [self createVariableWithName:variableIdentifier];
    
    return variable;
}

-(CSWVariable*)getOrCreateVariableWithName: (NSString*)name {
    CSWVariable *existingVariable = [self varibleWithName:name];
    if (existingVariable != nil) {
        return existingVariable;
    }
    
    return [self createVariableWithName:name];
}

-(CSWVariable*)createVariableWithName: (NSString*)name
{
    // TODO Fix hardcoded default value, this should really be nil or empty not zero and could lead to bugs
    CSWVariable *variable = [CSWVariable variableWithValue:0 name: name];
    [variablesByKey setObject: variable forKey: name];
    
    return variable;
}

-(NSString*)getVariableIdentifierForView: (NSView*)view withAttribute: (GSLayoutAttribute)attribute
{
    NSString *viewIdentifier = [self getIdentifierForView: view];
    return [NSString stringWithFormat: @"%@.%@",viewIdentifier, [self getAttributeName:attribute]];
}

-(NSString*)getAttributeName: (GSLayoutAttribute)attribute
{
    switch (attribute) {
        case GSLayoutAttributeTop:
            return @"top";
        case GSLayoutAttributeBottom:
            return @"bottom";
        case GSLayoutAttributeLeading:
            return @"leading";
        case GSLayoutAttributeLeft:
            return @"left";
        case GSLayoutAttributeRight:
            return @"right";
        case GSLayoutAttributeTrailing:
            return @"trailing";
        case GSLayoutAttributeHeight:
            return @"height";
        case GSLayoutAttributeWidth:
            return @"width";
        case GSLayoutAttributeCenterX:
            return @"centerX";
        case GSLayoutAttributeCenterY:
            return @"centerY";
        case GSLayoutAttributeBaseline:
            return @"baseline";
        case GSLayoutAttributeFirstBaseline:
            return @"firstBaseline";
        case GSLayoutAttributeMinX:
            return @"minX";
        case GSLayoutAttributeMinY:
            return @"minY";
        case GSLayoutAttributeMaxX:
            return @"maxX";
        case GSLayoutAttributeMaxY:
            return @"maxY";
        default:
            [[NSException
                    exceptionWithName:@"Not handled"
                    reason:@"GSLayoutAttribute not handled"
                    userInfo:nil] raise];
            return nil;
    }
}

-(NSString*)getDynamicVariableIdentifierForView: (NSView*)view withViewAttribute: (GSLayoutViewAttribute)attribute
{
    NSString *viewIdentifier = [self getIdentifierForView: view];
    return [NSString stringWithFormat: @"%@.%@",viewIdentifier, [self getLayoutViewAttributeName:attribute]];
}

-(NSString*)getLayoutViewAttributeName: (GSLayoutViewAttribute)attribute
{
    switch (attribute) {
        case GSLayoutViewAttributeBaselineOffsetFromBottom:
            return @"baselineOffsetFromBottom";
        case GSLayoutViewAttributeFirstBaselineOffsetFromTop:
            return @"firstBaselineOffsetFromTop";
        case GSLayoutViewAttributeIntrinsicWidth:
            return @"intrinsicContentSize.width";
        case GSLayoutViewAttributeInstrinctHeight:
            return @"intrinsicContentSize.height";
        default:
            [[NSException
                exceptionWithName:@"GSLayoutViewAttribute Not handled"
                reason:@"The provided GSLayoutViewAttribute does not have a name"
                userInfo:nil] raise];
            return nil;
    }
}

-(CSWConstraint*)solverConstraintForConstraint:(NSLayoutConstraint*)constraint
{
    if ([constraint secondItem] == nil) {
        return [self solverConstraintForNonRelationalConstraint:constraint];
    } else {
        return [self solverConstraintForRelationalConstraint: constraint];
    }
}

-(CSWConstraint*)solverConstraintForNonRelationalConstraint: (NSLayoutConstraint*)constraint
{
    CSWVariable *firstItemConstraintVariable = [self variableForView: [constraint firstItem] andAttribute: (GSLayoutAttribute)[constraint firstAttribute]];
    CSWConstraint *newConstraint;
    switch ([constraint relation]) {
        case NSLayoutRelationLessThanOrEqual: {
            newConstraint = [CSWConstraint constraintWithLeftVariable: firstItemConstraintVariable operator: CSWConstraintOperatorLessThanOrEqual rightConstant: [constraint constant]];
            break;
        }
        case NSLayoutRelationEqual:
            newConstraint =  [CSWConstraint constraintWithLeftVariable: firstItemConstraintVariable operator: CSWConstraintOperatorEqual rightConstant: [constraint constant]];
            break;
        case NSLayoutRelationGreaterThanOrEqual:
            newConstraint = [CSWConstraint constraintWithLeftVariable: firstItemConstraintVariable operator: CSWConstraintOperationGreaterThanOrEqual rightConstant: [constraint constant]];
            break;
    }
    
    newConstraint.strength = [[CSWStrength alloc] initWithName:nil strength:constraint.priority];
    return newConstraint;
}

-(CSWConstraint*)solverConstraintForRelationalConstraint: (NSLayoutConstraint*)constraint
{
    CSWVariable *firstItemConstraintVariable = [self variableForView: [constraint firstItem] andAttribute: (GSLayoutAttribute)[constraint firstAttribute]];
    CSWVariable *secondItemConstraintVariable = [self variableForView: [constraint secondItem] andAttribute: (GSLayoutAttribute)[constraint secondAttribute]];
    
    CGFloat multiplier = [constraint multiplier];

    CSWConstraintOperator op = CSWConstraintOperatorEqual;
        switch ([constraint relation]) {
        case NSLayoutRelationEqual:
            op = CSWConstraintOperatorEqual;
            break;
        case NSLayoutRelationLessThanOrEqual:
            op = CSWConstraintOperatorLessThanOrEqual;
            break;
        case NSLayoutRelationGreaterThanOrEqual:
            op = CSWConstraintOperationGreaterThanOrEqual;
            break;
    }
    double constant = [self getConstantMultiplierForLayoutAttribute: [constraint secondAttribute]] * [constraint constant];

    CSWLinearExpression *rightExpression = [[CSWLinearExpression alloc]
                                            initWithVariable: secondItemConstraintVariable coefficient: multiplier constant: constant];
    CSWConstraint *newConstraint = [CSWConstraint constraintWithLeftVariable: firstItemConstraintVariable operator: op rightExpression: rightExpression];
    [newConstraint setStrength:[[CSWStrength alloc] initWithName:nil strength:constraint.priority]];
    return newConstraint;
}

-(int)getConstantMultiplierForLayoutAttribute: (NSLayoutAttribute)attribute
{
    switch (attribute) {
        case NSLayoutAttributeTop:
            return -1;
        case NSLayoutAttributeBottom:
            return 1;
        case NSLayoutAttributeLeading:
            return 1;
        case NSLayoutAttributeTrailing:
            return -1;
        case NSLayoutAttributeLeft:
            return 1;
        case NSLayoutAttributeRight:
            return -1;
        default:
            return 1;
    }
}

-(CSWConstraint*)getExistingConstraintForAutolayoutConstraint: (NSLayoutConstraint*)constraint
{
    return [constraintsByAutoLayoutConstaintHash objectForKey: constraint];
}

-(void)removeConstraint: (NSLayoutConstraint*)constraint
{
    CSWConstraint *solverConstraint = [self getExistingConstraintForAutolayoutConstraint:constraint];
    if (solverConstraint == nil) {
        return;
    }

    [self removeObserversFromConstraint:constraint];
    [self removeSolverConstraint:solverConstraint];

    NSArray *internalConstraints = [supportingConstraintsByConstraint objectForKey: solverConstraint];
    for (CSWConstraint *internalConstraint in internalConstraints) {
        [self removeSolverConstraint: internalConstraint];;
    }
    [supportingConstraintsByConstraint setObject: nil forKey: solverConstraint];
    
    [self updateAlignmentRectsForTrackedViews];
    [self removeConstraintAgainstViewConstraintsArray: constraint];

    if ([self hasConstraintsForView: [constraint firstItem]]) {
        [self removeInternalConstraintsForView: [constraint firstItem]];
    }
    if ([constraint secondItem] != nil && [self hasConstraintsForView: [constraint secondItem]]) {
        [self removeInternalConstraintsForView:[constraint secondItem]];
    }
}

-(BOOL)hasConstraintsForView: (NSView*)view
{
    NSNumber *viewIndex = [self indexForView: view];
    return [constraintsByViewIndex[viewIndex] count] == 0;
}

-(void) removeConstraintAgainstViewConstraintsArray: (NSLayoutConstraint*)constraint
{
    NSNumber *firstItemViewIndex = [self indexForView: [constraint firstItem]];
    NSMutableArray *constraintsForFirstItem = constraintsByViewIndex[firstItemViewIndex];

    NSUInteger indexOfConstraintInFirstItem = [constraintsForFirstItem indexOfObject: constraint];
    [constraintsForFirstItem removeObjectAtIndex: indexOfConstraintInFirstItem];

    if ([constraint secondItem] != nil) {
        NSNumber *secondItemViewIndexIndex = [self indexForView: [constraint secondItem]];
        NSMutableArray *constraintsForSecondItem = constraintsByViewIndex[secondItemViewIndexIndex];

        NSUInteger indexOfConstraintInSecondItem = [constraintsForSecondItem indexOfObject: constraint];
        [constraintsForSecondItem removeObjectAtIndex: indexOfConstraintInSecondItem];
    }
}

-(void)removeInternalConstraintsForView: (NSView*)view
{
    for (CSWConstraint *constraint in [internalConstraintsByViewIndex objectForKey: view]) {
        [self removeSolverConstraint: constraint];
    }
    [internalConstraintsByViewIndex setObject: nil forKey: view];
}

-(void)removeObserversFromConstraint: (NSLayoutConstraint*)constraint
{
    [constraint removeObserver:self forKeyPath:@"constant"];
}

-(void)removeConstraints: (NSArray*)constraints
{
    for (id constraint in constraints) {
        [self removeConstraint:constraint];
    }
}

-(BOOL)isActiveConstraint: (NSLayoutConstraint*)constraint
{
    return [self getExistingConstraintForAutolayoutConstraint: constraint] != nil;
}

-(void)debugSolver
{
    NSLog(@"%@", solver);
}

-(void)addSupportingSolverConstraint: (CSWConstraint*)supportingConstraint forSolverConstraint: (CSWConstraint*)constraint
{
    [self addSolverConstraint: supportingConstraint];

    if ([supportingConstraintsByConstraint objectForKey: constraint] == nil) {
        [supportingConstraintsByConstraint setObject: [NSMutableArray array] forKey: constraint];
    }
    [[supportingConstraintsByConstraint objectForKey: constraint] addObject: supportingConstraint];
}

-(void)addSolverConstraint: (CSWConstraint*)constraint
{
    [solverConstraints addObject: constraint];
    [solver addConstraint: constraint];
}

-(void)removeSolverConstraint: (CSWConstraint*)constraint
{
    [solver removeConstraint: constraint];
    [solverConstraints removeObject: constraint];
    [constraint release];
}

-(NSArray*)constraintsForView: (NSView*)view
{
    NSNumber *viewIndex = [self indexForView: view];
    if (!viewIndex) {
        return [NSArray array];
    }

    NSMutableArray *constraintsForView = [NSMutableArray array];
    for (NSLayoutConstraint *constraint in constraintsByViewIndex[viewIndex]) {
        if ([constraint firstItem] == view) {
            [constraintsForView addObject: constraint];
        }
    }
    
    return constraintsForView;
}

-(void)invalidateIntrinsicConentSizeForView: (NSView*)view
{
    // TODO Remove constraint if there is no metric for a dimension
    [self resolveVariableForView: view attribute: GSLayoutViewAttributeIntrinsicWidth];
    [self resolveVariableForView: view attribute: GSLayoutViewAttributeInstrinctHeight];
}

- (void)dealloc {
   [trackedViews release];
   trackedViews = nil;

   [viewAlignmentRectByViewIndex release];
   viewAlignmentRectByViewIndex = nil;

    [viewIndexByViewHash release];
    viewIndexByViewHash = nil;

    [constraintsByViewIndex release];
    constraintsByViewIndex = nil;

    [supportingConstraintsByConstraint release];
    supportingConstraintsByConstraint = nil;

    [constraintsByAutoLayoutConstaintHash release];
    constraintsByAutoLayoutConstaintHash = nil;

    [internalConstraintsByViewIndex release];
    internalConstraintsByViewIndex = nil;

    [solverConstraints release];
    solverConstraints = nil;

    [variablesByKey release];
    variablesByKey = nil;

    [solver dealloc];

    [super dealloc];
}

@end
