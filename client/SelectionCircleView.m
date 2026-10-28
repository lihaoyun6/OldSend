#import "SelectionCircleView.h"

static CGFloat OSShadowOffsetY(CGFloat offset) {
    static NSInteger majorVersion = -1;
    if (majorVersion < 0) {
        majorVersion = [[[UIDevice currentDevice] systemVersion] intValue];
    }
    /* iOS 3 and iOS 4 apply the shadow Y axis in opposite directions. */
    return majorVersion >= 4 ? offset : -offset;
}

@implementation SelectionCircleView


- (id)initWithFrame:(CGRect)frame {
    if ((self = [super initWithFrame:frame])) {
        self.backgroundColor = [UIColor clearColor];
        self.opaque = NO;
        self.userInteractionEnabled = NO;
    }
    return self;
}

- (void)setChecked:(BOOL)checked {
    if (_checked != checked) {
        _checked = checked;
        [self setNeedsDisplay];
    }
}

- (void)drawRect:(CGRect)rect {
    CGContextRef context = UIGraphicsGetCurrentContext();
    CGFloat side = self.bounds.size.width;
    CGRect circle = CGRectInset(self.bounds, 6.5f, 6.5f);

    CGContextSetShouldAntialias(context, true);

    if (_checked) {
        /* Drop shadow under the blue selection circle. */
        CGContextSaveGState(context);
        CGContextSetShadowWithColor(context, CGSizeMake(0.0f, OSShadowOffsetY(2.0f)), 4.0f,
                                    [UIColor colorWithWhite:0.0f alpha:0.52f].CGColor);
        CGContextSetFillColorWithColor(context,
                                       [UIColor colorWithRed:0.12f green:0.42f blue:0.80f alpha:1.0f].CGColor);
        CGContextAddEllipseInRect(context, circle);
        CGContextFillPath(context);
        CGContextRestoreGState(context);

        /* Second, subtle upward shadow for a glass-like thickness. */
        CGContextSaveGState(context);
        CGContextSetShadowWithColor(context, CGSizeMake(0.0f, OSShadowOffsetY(1.0f)), 2.0f,
                                    [UIColor colorWithWhite:0.0f alpha:0.5f].CGColor);
        CGContextSetFillColorWithColor(context,
                                       [UIColor colorWithRed:0.12f green:0.42f blue:0.80f alpha:1.0f].CGColor);
        CGContextAddEllipseInRect(context, circle);
        CGContextFillPath(context);
        CGContextRestoreGState(context);

        CGContextSaveGState(context);
        CGContextAddEllipseInRect(context, circle);
        CGContextClip(context);

        {
            CGFloat colors[8] = { 0.46f, 0.76f, 1.0f, 1.0f,
                                  0.12f, 0.42f, 0.80f, 1.0f };
            CGColorSpaceRef colorSpace = CGColorSpaceCreateDeviceRGB();
            CGGradientRef gradient = CGGradientCreateWithColorComponents(colorSpace, colors, NULL, 2);
            if (gradient != NULL) {
                CGContextDrawLinearGradient(context, gradient,
                                            CGPointMake(0, CGRectGetMinY(circle)),
                                            CGPointMake(0, CGRectGetMaxY(circle)), 0);
                CGGradientRelease(gradient);
            }
            CGColorSpaceRelease(colorSpace);
        }

        CGContextSetFillColorWithColor(context, [UIColor colorWithWhite:1.0f alpha:0.32f].CGColor);
        CGContextFillRect(context, CGRectMake(0, 0, self.bounds.size.width,
                                              self.bounds.size.height * 0.48f));
        CGContextRestoreGState(context);

        CGContextSetStrokeColorWithColor(context, [UIColor whiteColor].CGColor);
        CGContextSetLineWidth(context, 2.2f);
        CGContextAddEllipseInRect(context, circle);
        CGContextStrokePath(context);

        CGContextSaveGState(context);
        CGContextSetShadowWithColor(context, CGSizeMake(0.0f, OSShadowOffsetY(1.0f)), 1.5f,
                                    [UIColor colorWithWhite:0.0f alpha:0.36f].CGColor);
        CGContextSetStrokeColorWithColor(context, [UIColor whiteColor].CGColor);
        CGContextSetLineWidth(context, 2.8f);
        CGContextSetLineCap(context, kCGLineCapRound);
        CGContextSetLineJoin(context, kCGLineJoinRound);
        CGContextMoveToPoint(context, side * 0.35f, side * 0.52f - 1.0f);
        CGContextAddLineToPoint(context, side * 0.46f, side * 0.63f - 1.0f);
        CGContextAddLineToPoint(context, side * 0.64f, side * 0.43f - 1.0f);
        CGContextStrokePath(context);
        CGContextRestoreGState(context);
    } else {
        CGContextSetFillColorWithColor(context, [UIColor whiteColor].CGColor);
        CGContextAddEllipseInRect(context, circle);
        CGContextFillPath(context);

        CGContextSetStrokeColorWithColor(context,
                                        [UIColor colorWithWhite:0.72f alpha:1.0f].CGColor);
        CGContextSetLineWidth(context, 1.2f);
        CGContextAddEllipseInRect(context, circle);
        CGContextStrokePath(context);
    }
}

@end

