#import "GSAutoLayoutEngine.h"
#include "Kiwi/kiwi.h"
#include <map>
#include "AppKit/NSLayoutConstraint.h"

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
    kiwi::Solver *solver;
    std::map<std::string, kiwi::Variable*> variablesByKey;
    std::vector<kiwi::Constraint*> solverConstraints;
    std::map<NSUInteger, kiwi::Constraint*> constraintsByAutoLayoutConstaintHash;
    NSMutableArray *trackedVariables;
    NSDictionary *keypathByLayoutDynamicAttribute;
    NSDictionary *layoutDynamicAttributeByKeypath;
    NSMutableArray *trackedViews;
    NSMutableDictionary *viewIndexByViewHash;
    NSMutableDictionary *viewAlignmentRectByViewIndex;
    NSMutableDictionary *constraintsByViewIndex;
    int viewCounter;
}

- (instancetype)init {
    if (self = [super init]) {
        viewCounter = 0;
        solver = new kiwi::Solver();
        trackedVariables = [NSMutableArray array];
        keypathByLayoutDynamicAttribute = @{
            @(GSLayoutViewAttributeBaselineOffsetFromBottom): @"baselineOffsetFromBottom",
            @(GSLayoutViewAttributeFirstBaselineOffsetFromTop): @"firstBaselineOffsetFromTop",
            @(GSLayoutViewAttributeIntrinsicWidth): @"intrinsicContentSize.width",
            @(GSLayoutViewAttributeInstrinctHeight): @"intrinsicContentSize.height"
        };
        
        trackedViews = [NSMutableArray array];
        [trackedViews retain];

        viewAlignmentRectByViewIndex = [NSMutableDictionary dictionary];
        [viewAlignmentRectByViewIndex retain];

        viewIndexByViewHash = [NSMutableDictionary dictionary];
        [viewIndexByViewHash retain];

        constraintsByViewIndex = [NSMutableDictionary dictionary];
        [constraintsByViewIndex retain];
        
        NSArray *layoutDynamicAttributes = [keypathByLayoutDynamicAttribute allKeys];
        layoutDynamicAttributeByKeypath = [NSDictionary dictionaryWithObjects:layoutDynamicAttributes forKeys:[keypathByLayoutDynamicAttribute allValues]];
    }
    return self;
}

-(void) addInternalConstraintsToView: (NSView*)view
{
    kiwi::Variable *viewMinXVariable = [self variableForView:view andAttribute:GSLayoutAttributeMinX];
    kiwi::Constraint *minXConstraint = new kiwi::Constraint { *viewMinXVariable == 0 };
    [self addSolverConstraint:minXConstraint];

    kiwi::Variable *viewMinYVariable = [self variableForView:view andAttribute:GSLayoutAttributeMinY];
    kiwi::Constraint *minYConstraint = new kiwi::Constraint { *viewMinYVariable == 0 };
    [self addSolverConstraint:minYConstraint];
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
        kiwi::Variable *baselineVariable = [self getExistingVariableForView:view withVariable:attribute];
        CGFloat baseline = [view baselineOffsetFromBottom];
        solver->suggestValue(*baselineVariable, baseline);
    } else if (attribute == GSLayoutViewAttributeFirstBaselineOffsetFromTop) {
        kiwi::Variable *firstBaselineOffsetFromTopVariable = [self getExistingVariableForView:view withVariable:attribute];
        CGFloat firstBaselineOffsetFromTop = [view firstBaselineOffsetFromTop];
        solver->suggestValue(*firstBaselineOffsetFromTopVariable, firstBaselineOffsetFromTop);
    } else if (attribute == GSLayoutViewAttributeIntrinsicWidth) {
        kiwi::Variable *instrinctWidthVariable = [self getExistingVariableForView:view withVariable:attribute];
        CGFloat width = [view intrinsicContentSize].width;
        solver->suggestValue(*instrinctWidthVariable, width);
    } else if (attribute == GSLayoutViewAttributeInstrinctHeight) {
        kiwi::Variable *instrinctHeightVariable = [self getExistingVariableForView:view withVariable:attribute];
        CGFloat height = [view intrinsicContentSize].height;
        solver->suggestValue(*instrinctHeightVariable, height);
    }
    
    [self updateAlignmentRectsForTrackedViews];
}

-(NSRect)_solverAlignmentRectForView:(NSView *)view
{
    kiwi::Variable *minX = [self getExistingVariableForView:view withAttribute:GSLayoutAttributeMinX];
    kiwi::Variable *minY = [self getExistingVariableForView:view withAttribute:GSLayoutAttributeMinY];
    kiwi::Variable *width = [self getExistingVariableForView:view withAttribute:GSLayoutAttributeWidth];
    kiwi::Variable *height = [self getExistingVariableForView:view withAttribute:GSLayoutAttributeHeight];

    return NSMakeRect(minX->value(),minY->value(),width->value(),height->value());
}

-(BOOL)_solverCanSolveAlignmentRectForView: (NSView*)view {
    kiwi::Variable *minX = [self getExistingVariableForView:view withAttribute:GSLayoutAttributeMinX];
    if (!minX) {
        return NO;
    }
    kiwi::Variable *minY = [self getExistingVariableForView:view withAttribute:GSLayoutAttributeMinY];
    if (!minY) {
        return NO;
    }
    kiwi::Variable *width = [self getExistingVariableForView:view withAttribute:GSLayoutAttributeWidth];
    if (!width || !width->value()) {
        return NO;
    }
    kiwi::Variable *height = [self getExistingVariableForView:view withAttribute:GSLayoutAttributeHeight];
    if (!height || !width->value()) {
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
    solver->updateVariables();
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
    [self addSupportingInternalConstraintsToView:[constraint firstItem] forAttribute:[constraint firstAttribute]];
    
    if ([constraint secondItem]) {
        [self addSupportingInternalConstraintsToView:[constraint secondItem] forAttribute:[constraint secondAttribute]];
    }
    
    kiwi::Constraint *solverConstraint = [self solverConstraintForConstraint: constraint];
    constraintsByAutoLayoutConstaintHash[[constraint hash]] = solverConstraint;
    [self addObserverToConstraint:constraint];
    
    try {
        [self addSolverConstraint:solverConstraint];
    } catch (std::exception& e) {
        NSLog(@"Error adding an error constraint");
    }

    [self addConstraintAgainstViewConstraintsArray: constraint];
    
    [self updateAlignmentRectsForTrackedViews];
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

-(void)addSupportingInternalConstraintsToView: (NSView*)view forAttribute: (NSLayoutAttribute)attribute
{
    switch (attribute) {
        case NSLayoutAttributeTrailing:
        case NSLayoutAttributeLeading:
            [self addInternalWidthConstraintForView: view];
            break;
        case NSLayoutAttributeLeft:
        case NSLayoutAttributeRight:
            [self addInternalWidthLeftRightConstraintForView: view];
            break;
        case NSLayoutAttributeTop:
        case NSLayoutAttributeBottom:
            [self addInternalHeightConstraintForView: view];
            break;
        case NSLayoutAttributeCenterX:
            [self addInternalCenterXConstraintsForView:view];
            break;
        case NSLayoutAttributeCenterY:
            [self addInternalCenterYConstraintsForView:view];
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
    kiwi::Variable *widthConstraintVariable = [self variableForView: view andAttribute: GSLayoutAttributeWidth];
    kiwi::Variable *leadingVariable = [self variableForView:view andAttribute:GSLayoutAttributeLeading];
    kiwi::Variable * trailingVariable = [self variableForView:view andAttribute:GSLayoutAttributeTrailing];
    kiwi::Variable *minX = [self variableForView:view andAttribute:GSLayoutAttributeMinX];
    kiwi::Variable *maxX = [self variableForView:view andAttribute:GSLayoutAttributeMaxX];

    kiwi::Constraint *minXLeadingRelationshipConstraint = new kiwi::Constraint { *minX == *leadingVariable };
    kiwi::Constraint *maxXTrailingRelationshipConstraint = new kiwi::Constraint { *maxX == *trailingVariable };
    kiwi::Constraint *widthRelationshipToMaxXAndMinXConstraint = new kiwi::Constraint { *widthConstraintVariable == *maxX - *minX };
    
    [self addSolverConstraint:widthRelationshipToMaxXAndMinXConstraint];
    [self addSolverConstraint:minXLeadingRelationshipConstraint];
    [self addSolverConstraint: maxXTrailingRelationshipConstraint];
}

-(void)addInternalWidthLeftRightConstraintForView: (NSView*)view
{
    kiwi::Variable *widthConstraintVariable = [self variableForView: view andAttribute: GSLayoutAttributeWidth];

    kiwi::Variable *minX = [self variableForView:view andAttribute:GSLayoutAttributeMinX];
    kiwi::Variable *maxX = [self variableForView:view andAttribute:GSLayoutAttributeMaxX];
    kiwi::Constraint *widthRelationshipToMaxXAndMinXConstraint = new kiwi::Constraint { *widthConstraintVariable == *maxX - *minX };


    kiwi::Variable *leftVariable = [self variableForView:view andAttribute:GSLayoutAttributeLeft];
    kiwi::Variable *rightVariable = [self variableForView:view andAttribute:GSLayoutAttributeRight];
    kiwi::Constraint *minXLeadingRelationshipConstraint = new kiwi::Constraint { *minX == *leftVariable };
    kiwi::Constraint *maxXRightRelationshipConstraint = new kiwi::Constraint { *maxX == *rightVariable };

    [self addSolverConstraint:widthRelationshipToMaxXAndMinXConstraint];
    [self addSolverConstraint:minXLeadingRelationshipConstraint];
    [self addSolverConstraint: maxXRightRelationshipConstraint];
}

-(void)addInternalHeightConstraintForView: (NSView*)view
{
    kiwi::Variable *heightConstraintVariable = [self variableForView: view andAttribute: GSLayoutAttributeHeight];
    kiwi::Variable *minY = [self variableForView:view andAttribute:GSLayoutAttributeMinY];
    kiwi::Variable *maxY = [self variableForView:view andAttribute:GSLayoutAttributeMaxY];
    kiwi::Constraint *heightConstraint = new kiwi::Constraint { *heightConstraintVariable == *maxY - *minY };
    [self addSolverConstraint:heightConstraint];

    kiwi::Variable *topVariable = [self variableForView:view andAttribute:GSLayoutAttributeTop];
    kiwi::Variable *bottomVariable = [self variableForView:view andAttribute:GSLayoutAttributeBottom];;
    kiwi::Constraint *minYBottomRelationshipConstraint = new kiwi::Constraint { *minY == *bottomVariable };
    kiwi::Constraint *maxYTopRelationshipConstraint = new kiwi::Constraint { *maxY == *topVariable };

    [self addSolverConstraint:minYBottomRelationshipConstraint];
    [self addSolverConstraint:maxYTopRelationshipConstraint];
}

-(void)addInternalCenterXConstraintsForView: (NSView*)view
{
    kiwi::Variable *centerXVariable = [self variableForView:view andAttribute:GSLayoutAttributeCenterX];
    kiwi::Variable *width = [self variableForView:view andAttribute:GSLayoutAttributeWidth];
    kiwi::Variable *minX = [self variableForView:view andAttribute:GSLayoutAttributeMinX];
    
    kiwi::Constraint *centerXConstraint = new kiwi::Constraint { *centerXVariable == *minX + (*width / 2) };
    [self addSolverConstraint:centerXConstraint];
}

-(void)addInternalCenterYConstraintsForView: (NSView*)view
{
    kiwi::Variable *centerYVariable = [self variableForView:view andAttribute:GSLayoutAttributeCenterY];
    kiwi::Variable *height = [self variableForView: view andAttribute:GSLayoutAttributeHeight];
    kiwi::Variable *minY = [self variableForView:view andAttribute:GSLayoutAttributeMinY];
    
    kiwi::Constraint *centerYConstraint = new kiwi::Constraint { *centerYVariable == *minY + (*height / 2) };
    [self addSolverConstraint:centerYConstraint];
}

-(void)addInternalFirstBaselineConstraintsForView: (NSView*)view
{
    // Requires internal top constraint to solve
    [self addInternalHeightConstraintForView:view];
    
    kiwi::Variable *firstBaselineVariable = [self variableForView:view andAttribute:GSLayoutAttributeFirstBaseline];
    kiwi::Variable *top = [self variableForView:view andAttribute:GSLayoutAttributeTop];
    kiwi::Variable *firstBaselineOffsetVariable = [self variableForView: view andViewAttribute:GSLayoutViewAttributeFirstBaselineOffsetFromTop];
    
    [self resolveAndObserveViewAttribute:GSLayoutViewAttributeFirstBaselineOffsetFromTop view:view];
    kiwi::Constraint *firstBaselineConstraint = new kiwi::Constraint {
        *firstBaselineVariable == *top - *firstBaselineOffsetVariable
    };
    [self addSolverConstraint:firstBaselineConstraint];
}

-(void)addInternalBaselineConstraintsForView: (NSView*)view
{
    kiwi::Variable *baselineVariable = [self variableForView:view andAttribute:GSLayoutAttributeBaseline];
    kiwi::Variable *minY = [self variableForView:view andAttribute:GSLayoutAttributeMinY];
    kiwi::Variable *baselineOffsetVariable = [self variableForView: view andViewAttribute:GSLayoutViewAttributeBaselineOffsetFromBottom];

    [self resolveAndObserveViewAttribute:GSLayoutViewAttributeBaselineOffsetFromBottom view:view];

    kiwi::Constraint *baselineConstraint = new kiwi::Constraint {
        *baselineVariable == *minY + *baselineOffsetVariable
    };
    [self addSolverConstraint:baselineConstraint];
}

-(void)addIntrinsicContentSizeConstraintsToView: (NSView*)view
{
    [self addSupportingInstrictSizeConstraintsToView:view orientation:NSLayoutConstraintOrientationHorizontal instrinctSizeAttribute:GSLayoutViewAttributeIntrinsicWidth dimensionAttribute:GSLayoutAttributeWidth];
    
    [self addSupportingInstrictSizeConstraintsToView:view orientation:NSLayoutConstraintOrientationVertical
        instrinctSizeAttribute: GSLayoutViewAttributeInstrinctHeight
        dimensionAttribute:GSLayoutAttributeHeight];
}

-(void)addSupportingInstrictSizeConstraintsToView: (NSView*)view orientation: (NSLayoutConstraintOrientation)orientation instrinctSizeAttribute: (GSLayoutViewAttribute)instrinctSizeAttribute dimensionAttribute: (GSLayoutAttribute)dimensionAttribute {
    kiwi::Variable *instrinctContentDimension = [self variableForView:view andViewAttribute:instrinctSizeAttribute];
    kiwi::Variable *dimensionVariable = [self variableForView:view andAttribute:dimensionAttribute];
    [self resolveVariableForView:view attribute:instrinctSizeAttribute];

    double huggingPriority = [view contentHuggingPriorityForOrientation:orientation];
    double huggingConstraintStrength = [self constraintStrengthForPriority:huggingPriority];
    kiwi::Constraint *huggingConstraint = new kiwi::Constraint {
        *dimensionVariable <= *instrinctContentDimension | huggingConstraintStrength
    };
    [self addSolverConstraint:huggingConstraint];
    
    double compressionPriority = [view contentCompressionResistancePriorityForOrientation:orientation];
    double compressionConstraintStrength =  [self constraintStrengthForPriority:compressionPriority];
    
    kiwi::Constraint *compressionConstraint = new kiwi::Constraint {
        *dimensionVariable >= *instrinctContentDimension | compressionConstraintStrength
    };
    [self addSolverConstraint:compressionConstraint];
}

/**
 * Updates the kiwi variable to the current value of the dynamic variable and setups observer to watch for future changes
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
    kiwi::Constraint *kConstraint = [self getExistingConstraintForAutolayoutConstraint:constraint];
    [self removeSolverConstraint:kConstraint];
    
    kiwi::Constraint *newKConstraint = [self solverConstraintForConstraint:constraint];
    constraintsByAutoLayoutConstaintHash[[constraint hash]] = newKConstraint;
    [self addSolverConstraint:newKConstraint];

    [self updateAlignmentRectsForTrackedViews];
}

-(void)addConstraints: (NSArray*)constraints
{
    for (id constraint in constraints) {
        [self addConstraint:constraint];
    }
}

-(kiwi::Variable*)variableForView:(NSView*)view andAttribute: (GSLayoutAttribute)attribute
{
    kiwi::Variable *existingVariable = [self getExistingVariableForView:view withAttribute:(GSLayoutAttribute)attribute];
    if (existingVariable != nil) {
        return existingVariable;
    } else {
        return [self createVariableForView: view withAttribute: attribute];
    }
}

-(kiwi::Variable*)variableForView: (NSView*)view andViewAttribute: (GSLayoutViewAttribute)attribute
{
    kiwi::Variable *existingVariable = [self getExistingVariableForView:view withVariable:attribute];
    if (existingVariable != nil) {
        return existingVariable;
    } else {
        return [self createVariableForView:view attribute:attribute];
    }
}

-(kiwi::Variable*)getExistingVariableForView:(NSView*)view withAttribute: (GSLayoutAttribute)attribute
{
    NSString *variableIdentifier = [self getVariableIdentifierForView: view withAttribute: (GSLayoutAttribute)attribute];
    return [self varibleWithName:variableIdentifier];
}

-(kiwi::Variable*)getExistingVariableForView: (NSView*)view withVariable: (GSLayoutViewAttribute)attribute
{
    NSString *variableIdentifier = [self getDynamicVariableIdentifierForView:view withViewAttribute:attribute];
    return [self varibleWithName:variableIdentifier];
}

-(kiwi::Variable*) varibleWithName:(NSString*)variableName
{
    std::string viewIdStr = std::string([variableName UTF8String]);

    if (variablesByKey.find(viewIdStr) != variablesByKey.end()) {
        return variablesByKey[viewIdStr];
    }
    return nil;
}

-(kiwi::Variable*)createVariableForView:(NSView*)view withAttribute: (GSLayoutAttribute)attribute
{
    NSString *variableIdentifier = [self getVariableIdentifierForView: view withAttribute: attribute];
    
    kiwi::Variable *variable = [self createVariableWithName:variableIdentifier];
    
    return variable;
}

-(kiwi::Variable*)createVariableForView:(NSView*)view attribute: (GSLayoutViewAttribute)attribute
{
    NSString *variableIdentifier = [self getDynamicVariableIdentifierForView:view withViewAttribute:attribute];
    kiwi::Variable *variable = [self createVariableWithName:variableIdentifier];

    solver->addEditVariable(*variable, kiwi::strength::strong);
    NSDictionary *trackedVariable = @{
        @"view" : view,
        @"attribute" : [NSNumber numberWithInteger: attribute],
    };
    [trackedVariables addObject:trackedVariable];
    
    return variable;
}

-(kiwi::Variable*)getOrCreateVariableWithName: (NSString*)name {
    kiwi::Variable *existingVariable = [self varibleWithName:name];
    if (existingVariable != nil) {
        return existingVariable;
    }
    
    return [self createVariableWithName:name];
}

-(kiwi::Variable*)createVariableWithName: (NSString*)name
{
    std::string viewIdStr = std::string([name UTF8String]);
    kiwi::Variable *varible = new kiwi::Variable(viewIdStr);
    variablesByKey[viewIdStr] = varible;
    
    return varible;
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
            NSException* myException = [NSException
                    exceptionWithName:@"Not handled"
                    reason:@"File Not Found on System"
                    userInfo:nil];
            [myException raise];
            return @"";
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

-(kiwi::Constraint*)solverConstraintForConstraint:(NSLayoutConstraint*)constraint
{
    if ([constraint secondItem] == nil) {
        return [self solverConstraintForNonRelationalConstraint:constraint];
    } else {
        return [self solverConstraintForRelationalConstraint: constraint];
    }
}

-(kiwi::Constraint*)solverConstraintForNonRelationalConstraint: (NSLayoutConstraint*)constraint
{
    kiwi::Variable *firstItemConstraintVariable = [self variableForView: [constraint firstItem] andAttribute: (GSLayoutAttribute)[constraint firstAttribute]];
    double constraintStrength = [self constraintStrengthForPriority:constraint.priority];
    switch ([constraint relation]) {
        case NSLayoutRelationLessThanOrEqual:
            return new kiwi::Constraint { *firstItemConstraintVariable <= [constraint constant] | constraintStrength };
        case NSLayoutRelationEqual:
            return new kiwi::Constraint { *firstItemConstraintVariable == [constraint constant] | constraintStrength };
        case NSLayoutRelationGreaterThanOrEqual:
            return new kiwi::Constraint { *firstItemConstraintVariable >= [constraint constant] | constraintStrength };
    }
}

-(kiwi::Constraint*)solverConstraintForRelationalConstraint: (NSLayoutConstraint*)constraint
{
    kiwi::Variable *firstItemConstraintVariable = [self variableForView: [constraint firstItem] andAttribute: (GSLayoutAttribute)[constraint firstAttribute]];
    kiwi::Variable *secondItemConstraintVariable = [self variableForView: [constraint secondItem] andAttribute: (GSLayoutAttribute)[constraint secondAttribute]];
    
    double constraintStrength = [self constraintStrengthForPriority:constraint.priority];
    CGFloat multiplier = [constraint multiplier];
    
    switch ([constraint relation]) {
        case NSLayoutRelationEqual:
            return new kiwi::Constraint { *firstItemConstraintVariable == multiplier * *secondItemConstraintVariable + [self getConstantMultiplierForLayoutAttribute: [constraint secondAttribute]] * [constraint constant] | constraintStrength };
        case NSLayoutRelationLessThanOrEqual:
            return new kiwi::Constraint { *firstItemConstraintVariable <= multiplier * *secondItemConstraintVariable + [self getConstantMultiplierForLayoutAttribute: [constraint secondAttribute]] * [constraint constant] | constraintStrength };
        case NSLayoutRelationGreaterThanOrEqual:
            return new kiwi::Constraint { *firstItemConstraintVariable >= multiplier * *secondItemConstraintVariable + [self getConstantMultiplierForLayoutAttribute: [constraint secondAttribute]] * [constraint constant] | constraintStrength };
    }
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

-(double)constraintStrengthForPriority: (NSLayoutPriority)priority
{
    return MAX(0.0, MIN(1000.0, priority)) * 1000000.0;
}

-(kiwi::Constraint*)getExistingConstraintForAutolayoutConstraint: (NSLayoutConstraint*)constraint
{
    NSUInteger constraintHash = [constraint hash];
    if (constraintsByAutoLayoutConstaintHash.find(constraintHash) != constraintsByAutoLayoutConstaintHash.end()) {
        return constraintsByAutoLayoutConstaintHash[constraintHash];
    }
    return nil;
}

-(void)removeConstraint: (NSLayoutConstraint*)constraint
{
    kiwi::Constraint *kConstraint = [self getExistingConstraintForAutolayoutConstraint:constraint];
    if (kConstraint == nil) {
        return;
    }

    [self removeObserverFromConstraint:constraint];
    [self removeSolverConstraint:kConstraint];
    
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
    std::string dump = solver->dumps();
    NSString *debug = [NSString stringWithCString:dump.c_str()
    encoding:[NSString defaultCStringEncoding]];
    NSLog(@"%@", debug);
}

-(void)addSolverConstraint: (kiwi::Constraint*)constraint
{
    solverConstraints.push_back(constraint);
    solver->addConstraint(*constraint);
}

-(void)removeSolverConstraint: (kiwi::Constraint*)constraint
{
    solver->removeConstraint(*constraint);
    solverConstraints.erase(std::remove(solverConstraints.begin(), solverConstraints.end(), constraint), solverConstraints.end());
    delete constraint;
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

    delete solver;
    [self deallocSolverVariables];
    [self deallocSolverConstraints];
    [super dealloc];
}

-(void)deallocSolverVariables
{
    std::map<std::string, kiwi::Variable*>::iterator variableByIterator;
    for (variableByIterator = variablesByKey.begin(); variableByIterator != variablesByKey.end(); variableByIterator++)
    {
        delete variableByIterator->second;
    }
}

-(void)deallocSolverConstraints
{
    for (const kiwi::Constraint *constraint: solverConstraints) {
        delete constraint;
    }
}

@end
