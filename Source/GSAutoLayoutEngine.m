#import "GSAutoLayoutEngine.h"
#include "AppKit/NSLayoutConstraint.h"
#include "CSWConstraint.h"

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
    NSMutableArray *trackedVariables;
    NSDictionary *keypathByLayoutDynamicAttribute;
    NSDictionary *layoutDynamicAttributeByKeypath;
    NSMutableArray *trackedViews;
    NSMutableDictionary *viewIndexByViewHash;
    NSMutableDictionary *viewAlignmentRectByViewIndex;
    NSMutableDictionary *constraintsByViewIndex;
    NSMutableDictionary *internalConstraintsByViewIndex;
    NSMapTable *supportingConstraintsByConstraint;
    int viewCounter;
}

-(instancetype)initWithSolver: (CSWSimplexSolver*)simplexSolver
{
    if (self = [super init]) {
        viewCounter = 0;
        solver = simplexSolver;
        trackedVariables = [NSMutableArray array];
        keypathByLayoutDynamicAttribute = @{
            @(GSLayoutViewAttributeBaselineOffsetFromBottom): @"baselineOffsetFromBottom",
            @(GSLayoutViewAttributeFirstBaselineOffsetFromTop): @"firstBaselineOffsetFromTop",
            @(GSLayoutViewAttributeIntrinsicWidth): @"intrinsicContentSize.width",
            @(GSLayoutViewAttributeInstrinctHeight): @"intrinsicContentSize.height"
        };

        variablesByKey = [NSMapTable strongToStrongObjectsMapTable];

        constraintsByAutoLayoutConstaintHash = [NSMapTable strongToStrongObjectsMapTable];

        solverConstraints = [NSMutableArray array];
        [solverConstraints retain];
        
        trackedViews = [NSMutableArray array];
        [trackedViews retain];

        supportingConstraintsByConstraint = [NSMapTable strongToStrongObjectsMapTable];

        viewAlignmentRectByViewIndex = [NSMutableDictionary dictionary];
        [viewAlignmentRectByViewIndex retain];

        viewIndexByViewHash = [NSMutableDictionary dictionary];
        [viewIndexByViewHash retain];

        constraintsByViewIndex = [NSMutableDictionary dictionary];
        [constraintsByViewIndex retain];
        
        internalConstraintsByViewIndex = [NSMutableDictionary dictionary];
        
        NSArray *layoutDynamicAttributes = [keypathByLayoutDynamicAttribute allKeys];
        layoutDynamicAttributeByKeypath = [NSDictionary dictionaryWithObjects:layoutDynamicAttributes forKeys:[keypathByLayoutDynamicAttribute allValues]];
    }
    return self;
}

- (instancetype)init {
    CSWSimplexSolver *solver = [[CSWSimplexSolver alloc] init];
    return [self initWithSolver: solver];
}

-(void)resolveVariables {
    for (id trackedVariable in trackedVariables) {
        NSView *view = trackedVariable[@"view"];
        GSLayoutViewAttribute attribute = (GSLayoutViewAttribute)[(NSNumber*)trackedVariable[@"attribute"] integerValue];
        [self resolveVariableForView:view attribute:attribute];
    }
}

-(void)resolveVariableForView: (NSView*)view attribute: (GSLayoutViewAttribute)attribute
{
    if (attribute == GSLayoutViewAttributeBaselineOffsetFromBottom) {
        CSWVariable *baselineVariable = [self getExistingVariableForView:view withVariable:attribute];
        CGFloat baseline = [view baselineOffsetFromBottom];
        CSWConstraint *baselineEditConstraint = [CSWConstraint editConstraintWithVariable:baselineVariable];
        
        [solver addConstraint:baselineEditConstraint];
        [solver suggestEditVariable:baselineVariable equals:baseline];
        [solver resolve];
    } else if (attribute == GSLayoutViewAttributeFirstBaselineOffsetFromTop) {
        CSWVariable *firstBaselineOffsetFromTopVariable = [self getExistingVariableForView:view withVariable:attribute];
        CGFloat firstBaselineOffsetFromTop = [view firstBaselineOffsetFromTop];
        
        CSWConstraint *firstBaselineEditConstraint = [CSWConstraint editConstraintWithVariable:firstBaselineOffsetFromTopVariable];
        [solver addConstraint:firstBaselineEditConstraint];
        [solver suggestEditVariable:firstBaselineOffsetFromTopVariable equals:firstBaselineOffsetFromTop];
        [solver resolve];
    } else if (attribute == GSLayoutViewAttributeIntrinsicWidth) {
        CSWVariable *instrinctWidthVariable = [self getExistingVariableForView:view withVariable:attribute];
        CGFloat width = [view intrinsicContentSize].width;
        
        CSWConstraint *instrinctWidthEditConstraint = [CSWConstraint editConstraintWithVariable:instrinctWidthVariable];
        [solver addConstraint:instrinctWidthEditConstraint];
        [solver suggestEditVariable:instrinctWidthVariable equals:width];
        [solver resolve];
    } else if (attribute == GSLayoutViewAttributeInstrinctHeight) {
        CSWVariable *instrinctHeightVariable = [self getExistingVariableForView:view withVariable:attribute];
        CGFloat height = [view intrinsicContentSize].height;
        
        CSWConstraint *instrinctHeightEditConstraint = [CSWConstraint editConstraintWithVariable:instrinctHeightVariable];
        [solver addConstraint:instrinctHeightEditConstraint];
        [solver suggestEditVariable:instrinctHeightVariable equals:height];
        [solver resolve];
    }
    
    [self updateAlignmentRectsForTrackedViews];
}

-(NSRect)_solverAlignmentRectForView:(NSView *)view
{
    CSWVariable *minX = [self getExistingVariableForView:view withAttribute:GSLayoutAttributeMinX];
    CSWVariable *minY = [self getExistingVariableForView:view withAttribute:GSLayoutAttributeMinY];
    CSWVariable *width = [self getExistingVariableForView:view withAttribute:GSLayoutAttributeWidth];
    CSWVariable *height = [self getExistingVariableForView:view withAttribute:GSLayoutAttributeHeight];

    return NSMakeRect([minX value], [minY value], [width value], [height value]);
}

-(BOOL)_solverCanSolveAlignmentRectForView: (NSView*)view {
    CSWVariable *minX = [self getExistingVariableForView:view withAttribute:GSLayoutAttributeMinX];
    if (!minX) {
        return NO;
    }
    CSWVariable *minY = [self getExistingVariableForView:view withAttribute:GSLayoutAttributeMinY];
    if (!minY) {
        return NO;
    }
    CSWVariable *width = [self getExistingVariableForView:view withAttribute:GSLayoutAttributeWidth];
    if (!width || ![width value]) {
        return NO;
    }
    CSWVariable *height = [self getExistingVariableForView:view withAttribute:GSLayoutAttributeHeight];
    if (!height || ![height value]) {
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
    [solver solve];
    [solver resolve];
    NSMutableArray *viewsWithChanges = [NSMutableArray array];
    for (NSView *view in trackedViews) {
        NSNumber *viewIndex = [self indexForView:view];
        if ([self _solverCanSolveAlignmentRectForView: view]) {
            NSRect existingAlignmentRect = [self currentAlignmentRectForViewAtIndex:viewIndex];
            BOOL isExistingAlignmentRect = [self isValidNSRect: existingAlignmentRect];
            NSRect solverAlignmentRect = [self _solverAlignmentRectForView:view];
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

-(NSRect)getExistingAlignmentRectFromForViewOrDetermineFromSolver: (NSView*)view
{
    NSNumber *viewIndex = [self indexForView:view];
    NSRect existingRect = [self currentAlignmentRectForViewAtIndex:viewIndex];
    if (!NSIsEmptyRect(existingRect)) {
        return existingRect;
    }
    
    NSRect newAlignmentRect = [self _solverAlignmentRectForView:view];
    NSValue *newRectValue = [NSValue valueWithRect:newAlignmentRect];
    [viewAlignmentRectByViewIndex setObject:newRectValue forKey:viewIndex];\
    return newAlignmentRect;
}

-(NSRect)currentAlignmentRectForViewAtIndex: (NSNumber*)viewIndex
{
    NSValue *existingRectValue = [viewAlignmentRectByViewIndex objectForKey:viewIndex];
    if (!existingRectValue) {
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
}

-(void) removeConstraintAgainstViewConstraintsArray: (NSLayoutConstraint*)constraint
{
     NSNumber *firstItemViewIndex = [self indexForView: [constraint firstItem]];
     NSMutableArray *constraintsForView = constraintsByViewIndex[firstItemViewIndex];

     NSUInteger indexOfConstraint = [constraintsForView indexOfObject: constraint];
     [constraintsForView removeObjectAtIndex: indexOfConstraint];
}

-(BOOL)hasAddedWidthAndHeightConstraintsToView: (NSView*)view
{
    NSNumber *viewIndex = [self indexForView: view];
    NSNumber *added = internalConstraintsByViewIndex[viewIndex];
    return added != nil;
}

-(void)addSupportingInternalConstraintsToView: (NSView*)view forAttribute: (NSLayoutAttribute)attribute constraint: (CSWConstraint*)constraint
{
    if (![self hasAddedWidthAndHeightConstraintsToView: view]) {
        [self addInternalWidthConstraintForView: view];
        [self addInternalHeightConstraintForView: view];
        [internalConstraintsByViewIndex setObject: [NSNumber numberWithBool: YES] forKey: [self indexForView: view]];
    }

    switch (attribute) {
        case NSLayoutAttributeTrailing:
        case NSLayoutAttributeLeading:
            [self addInternalLeadingTrailingConstraintsForView: view];
            break;
        case NSLayoutAttributeLeft:
        case NSLayoutAttributeRight:
            [self addInternalWidthLeftRightConstraintsForView: view];
            break;
        case NSLayoutAttributeTop:
        case NSLayoutAttributeBottom:
            [self addInternalTopBottomConstraintsForView: view];
            break;
        case NSLayoutAttributeCenterX:
            [self addInternalCenterXConstraintsForView:view constraint: constraint];
            break;
        case NSLayoutAttributeCenterY:
            [self addInternalCenterYConstraintsForView:view constraint: constraint];
            break;
        case NSLayoutAttributeBaseline:
            [self addInternalBaselineConstraintsForView:view];
            break;
        case NSLayoutAttributeFirstBaseline:
            [self addInternalFirstBaselineConstraintsForView: view];
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
    
    [self addSolverConstraint:widthRelationshipToMaxXAndMinXConstraint];
}

-(void)addInternalHeightConstraintForView: (NSView*)view
{
    CSWVariable *heightConstraintVariable = [self variableForView: view andAttribute: GSLayoutAttributeHeight];
    CSWVariable *minY = [self variableForView:view andAttribute:GSLayoutAttributeMinY];
    CSWVariable *maxY = [self variableForView:view andAttribute:GSLayoutAttributeMaxY];

    CSWLinearExpression *maxYMinusMinY = [[CSWLinearExpression alloc] initWithVariable: maxY];
    [maxYMinusMinY addVariable: minY coefficient: -1];
    CSWConstraint *heightConstraint = [CSWConstraint constraintWithLeftVariable: heightConstraintVariable operator:CSWConstraintOperatorEqual rightExpression: maxYMinusMinY];
    [self addSolverConstraint:heightConstraint];
}

-(void)addInternalLeadingTrailingConstraintsForView: (NSView*)view
{
    CSWVariable *minX = [self variableForView:view andAttribute:GSLayoutAttributeMinX];
    CSWVariable *leadingVariable = [self variableForView:view andAttribute:GSLayoutAttributeLeading];
    CSWConstraint *minXLeadingRelationshipConstraint = [CSWConstraint constraintWithLeftVariable: minX operator:CSWConstraintOperatorEqual rightVariable: leadingVariable];
    [self addSolverConstraint:minXLeadingRelationshipConstraint];

    CSWVariable * trailingVariable = [self variableForView:view andAttribute:GSLayoutAttributeTrailing];
    CSWVariable *maxX = [self variableForView:view andAttribute:GSLayoutAttributeMaxX];
    CSWConstraint *maxXTrailingRelationshipConstraint = [CSWConstraint constraintWithLeftVariable: maxX operator:CSWConstraintOperatorEqual rightVariable: trailingVariable];
    [self addSolverConstraint: maxXTrailingRelationshipConstraint];
}

-(void)addInternalWidthLeftRightConstraintsForView: (NSView*)view
{
    CSWVariable *minX = [self variableForView:view andAttribute:GSLayoutAttributeMinX];
    CSWVariable *leftVariable = [self variableForView:view andAttribute:GSLayoutAttributeLeft];
    CSWConstraint *minXLeadingRelationshipConstraint = [CSWConstraint constraintWithLeftVariable: minX operator:CSWConstraintOperatorEqual rightVariable: leftVariable];
    [self addSolverConstraint:minXLeadingRelationshipConstraint];

    CSWVariable *maxX = [self variableForView:view andAttribute:GSLayoutAttributeMaxX];
    CSWVariable *rightVariable = [self variableForView:view andAttribute:GSLayoutAttributeRight];
    CSWConstraint *maxXRightRelationshipConstraint = [CSWConstraint constraintWithLeftVariable: maxX operator:CSWConstraintOperatorEqual rightVariable: rightVariable];
    [self addSolverConstraint: maxXRightRelationshipConstraint];
}

-(void)addInternalTopBottomConstraintsForView: (NSView*)view
{
    CSWVariable *minY = [self variableForView:view andAttribute:GSLayoutAttributeMinY];
    CSWVariable *bottomVariable = [self variableForView:view andAttribute:GSLayoutAttributeBottom];
    CSWConstraint *minYBottomRelationshipConstraint = [CSWConstraint constraintWithLeftVariable: minY operator:CSWConstraintOperatorEqual rightVariable: bottomVariable];
    [self addSolverConstraint:minYBottomRelationshipConstraint];

    CSWVariable *maxY = [self variableForView:view andAttribute:GSLayoutAttributeMaxY];
    CSWVariable *topVariable = [self variableForView:view andAttribute:GSLayoutAttributeTop];
    CSWConstraint *maxYTopRelationshipConstraint = [CSWConstraint constraintWithLeftVariable: maxY operator:CSWConstraintOperatorEqual rightVariable: topVariable];
    [self addSolverConstraint:maxYTopRelationshipConstraint];
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

-(void)addInternalFirstBaselineConstraintsForView: (NSView*)view
{
    // Requires internal top constraint to solve
    [self addInternalTopBottomConstraintsForView:view];
    
    CSWVariable *firstBaselineVariable = [self variableForView:view andAttribute:GSLayoutAttributeFirstBaseline];
    CSWVariable *top = [self variableForView:view andAttribute:GSLayoutAttributeTop];
    CSWVariable *firstBaselineOffsetVariable = [self variableForView: view andViewAttribute:GSLayoutViewAttributeFirstBaselineOffsetFromTop];
    
    CSWLinearExpression *exp = [[CSWLinearExpression alloc] initWithVariable: top];
    [exp addVariable: firstBaselineOffsetVariable coefficient: -1];
    CSWConstraint *firstBaselineConstraint = [CSWConstraint constraintWithLeftVariable: firstBaselineVariable operator: CSWConstraintOperatorEqual rightExpression: exp];

    [self addSolverConstraint:firstBaselineConstraint];
    [self resolveAndObserveViewAttribute:GSLayoutViewAttributeFirstBaselineOffsetFromTop view:view];
}

-(void)addInternalBaselineConstraintsForView: (NSView*)view
{
    CSWVariable *baselineVariable = [self variableForView:view andAttribute:GSLayoutAttributeBaseline];
    CSWVariable *minY = [self variableForView:view andAttribute:GSLayoutAttributeMinY];
    CSWVariable *baselineOffsetVariable = [self variableForView: view andViewAttribute:GSLayoutViewAttributeBaselineOffsetFromBottom];

    [self resolveAndObserveViewAttribute:GSLayoutViewAttributeBaselineOffsetFromBottom view:view];
    CSWLinearExpression *exp = [[CSWLinearExpression alloc] initWithVariable: minY];
    [exp addVariable: baselineOffsetVariable];
    CSWConstraint *baselineConstraint = [CSWConstraint constraintWithLeftVariable: baselineVariable operator: CSWConstraintOperatorEqual rightExpression: exp];

    [self addSolverConstraint:baselineConstraint];
}

-(void)addIntrinsicContentSizeConstraintsToView: (NSView*)view
{
    [self addSupportingInstrictSizeConstraintsToView:view orientation:NSLayoutConstraintOrientationHorizontal instrinctSizeAttribute:GSLayoutViewAttributeIntrinsicWidth dimensionAttribute:GSLayoutAttributeWidth];
    
    [self addSupportingInstrictSizeConstraintsToView:view orientation:NSLayoutConstraintOrientationVertical
                               instrinctSizeAttribute: GSLayoutViewAttributeInstrinctHeight
                                   dimensionAttribute:GSLayoutAttributeHeight];
     
    [self updateAlignmentRectsForTrackedViews];
}

-(void)addSupportingInstrictSizeConstraintsToView: (NSView*)view orientation: (NSLayoutConstraintOrientation)orientation instrinctSizeAttribute: (GSLayoutViewAttribute)instrinctSizeAttribute dimensionAttribute: (GSLayoutAttribute)dimensionAttribute {
    CSWVariable *instrinctContentDimension = [self variableForView:view andViewAttribute:instrinctSizeAttribute];
    CSWVariable *dimensionVariable = [self variableForView:view andAttribute:dimensionAttribute];
    [self resolveVariableForView:view attribute:instrinctSizeAttribute];

    double huggingPriority = [view contentHuggingPriorityForOrientation:orientation];
    CSWConstraint *huggingConstraint = [CSWConstraint constraintWithLeftVariable: dimensionVariable operator: CSWConstraintOperatorLessThanOrEqual rightVariable: instrinctContentDimension];
    huggingConstraint.strength = [[CSWStrength alloc] initWithName:nil strength:huggingPriority];

    [self addSolverConstraint:huggingConstraint];
    
    double compressionPriority = [view contentCompressionResistancePriorityForOrientation:orientation];
    CSWConstraint *compressionConstraint = [CSWConstraint constraintWithLeftVariable: dimensionVariable operator: CSWConstraintOperationGreaterThanOrEqual rightVariable: instrinctContentDimension];
    compressionConstraint.strength = [[CSWStrength alloc] initWithName:nil strength:compressionPriority];

    [self addSolverConstraint:compressionConstraint];
}

/**
 * Updates the solver variable to the current value of the dynamic variable and setups observer to watch for future changes
 */
-(void)resolveAndObserveViewAttribute: (GSLayoutViewAttribute)attribute view: (NSView*)view
{
    [self resolveVariableForView:view attribute:attribute];
    NSString *keypath = keypathByLayoutDynamicAttribute[@(attribute)];
    [view addObserver:self forKeyPath:keypath options:NSKeyValueObservingOptionNew context:nil];
}

-(void)addObserverToConstraint: (NSLayoutConstraint*)constranit
{
    [constranit addObserver:self forKeyPath:@"constant" options:NSKeyValueObservingOptionNew context:nil];
}

-(void)removeObserverFromConstraint: (NSLayoutConstraint*)constraint
{
    [constraint removeObserver:self forKeyPath:@"constant"];
}

- (void)observeValueForKeyPath:(NSString *)keyPath ofObject:(id)object change:(NSDictionary *)change context:(void *)context {
    
    if ([object isKindOfClass:[NSLayoutConstraint class]]) {
        NSLayoutConstraint *constraint = (NSLayoutConstraint *)object;
        [self updateConstraint:constraint];
    } else if ([object isKindOfClass:[NSView class]]) {
        GSLayoutViewAttribute attribute = (GSLayoutViewAttribute)[(NSNumber*)layoutDynamicAttributeByKeypath[keyPath] integerValue];
        [self resolveVariableForView:object attribute:attribute];
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

    NSDictionary *trackedVariable = @{
        @"view" : view,
        @"attribute" : [NSNumber numberWithInteger: attribute],
    };
    [trackedVariables addObject:trackedVariable];
    
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
    NSString *keypath = keypathByLayoutDynamicAttribute[@(attribute)];
     if (keypath) {
        return keypath;
    } else {
        NSException* myException = [NSException
                exceptionWithName:@"GSLayoutViewAttribute Not handled"
                reason:@"The provided GSLayoutViewAttribute does not have a name"
                userInfo:nil];
        [myException raise];
        return NULL;
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
    CSWConstraint *kConstraint = [self getExistingConstraintForAutolayoutConstraint:constraint];
    if (kConstraint == nil) {
        return;
    }

    [self removeObserverFromConstraint:constraint];
    [self removeSolverConstraint:kConstraint];

    NSArray *internalConstraints = [supportingConstraintsByConstraint objectForKey: kConstraint];
    for (CSWConstraint *internalConstraint in internalConstraints) {
        [self removeSolverConstraint: internalConstraint];;
    }
    [supportingConstraintsByConstraint setObject: nil forKey: kConstraint];
    
    [self updateAlignmentRectsForTrackedViews];
    [self removeConstraintAgainstViewConstraintsArray: constraint];

    // TODO clean up internal constraints
    // TODO clean up observers of any dynamic attributes that relate to constraint
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
    // dealoc constraint
}

-(NSArray*)constraintsForView: (NSView*)view
{
    NSNumber *viewIndex = [self indexForView: view];
    if (!viewIndex) {
        return [NSArray array];
    }

    return [constraintsByViewIndex[viewIndex] copy];
}

- (void)dealloc {
   [trackedViews release];
   [viewAlignmentRectByViewIndex release];
   [viewIndexByViewHash release];
   [constraintsByViewIndex release];

    [solver dealloc];
    [self deallocSolverVariables];
    [self deallocSolverConstraints];
    [super dealloc];
}

-(void)deallocSolverVariables
{
}

-(void)deallocSolverConstraints
{
}

@end
