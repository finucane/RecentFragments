
//
//  ICPDFView.m
//  iConsult Enterprise
//
//  Created by finucane on 1/20/13.
//
//

#import "insist.h"
#import "ICPDFView.h"
#import "ICProvider.h"
#import <QuartzCore/QuartzCore.h>
#import "ICPatientVisit.h"
#import "ICPresentation.h"

#define PDF_ANNOTATION_KEY "Annots"
#define FIRST_TEXT_TAG 100
#define TEXT_FONT_NAME @"Verdana"
#define TEXT_FONT_SIZE 12
#define CHECKBOX_FONT_NAME @"Verdana"
#define CHECKBOX_FONT_SIZE 10
#define CHECKBOX_STRING @"X"
#define DATE_FORMAT @"MMMM dd, yyyy"
#define TIME_FORMAT @"hh:mm a"
#define DATE_AND_TIME_FORMAT @"MMMM dd, yyyy hh:mm a"
#define POINTER_OFFSET 25
#define POINTER_ALPHA 0.75
#define REQUIRED_MARK @"*"
#define MIN_TEXT_AREA_HEIGHT 30
#define LABEL_MIN_SCALE_FACTOR 0.5

/*a UIView that just draws a PDF page to itself*/
@interface ICPDFRenderingView : UIView
{
@private
    CGPDFPageRef page;
}
-(id)initWithFrame:(CGRect)frame page:(CGPDFPageRef)page;

@end

@implementation ICPDFRenderingView
-(id)initWithFrame:(CGRect)frame page:(CGPDFPageRef)aPage;
{
    if (self = [super initWithFrame:frame])
    {
        page = aPage;
    }
    return self;
}

/*draw a PDF, which has in an upside down coordinate system, into a UIKit coordinate system*/
-(void)drawRect:(CGRect)rect
{
    CGRect cropRect = CGRectIntegral(CGPDFPageGetBoxRect(page, kCGPDFCropBox));
    
    CGContextRef context = UIGraphicsGetCurrentContext();
    CGContextSaveGState (context);
    
    /*paint a white background*/
    CGContextSetRGBFillColor(context, 1.0, 1.0, 1.0, 1.0);
    CGContextFillRect(context, rect);
    
    CGContextClipToRect (context, cropRect);

    /*draw the pdf, upside down. pdfs are upside down to UIKit coordinates*/
    CGContextTranslateCTM(context, 0, self.bounds.size.height);
	CGContextScaleCTM(context, 1.0, -1.0);
    CGContextDrawPDFPage(context, page);
    CGContextRestoreGState (context);
}
@end


@implementation ICPDFView

/*return pdf data for the page*/
-(NSData *)pdf
{
    insist (self);
    
    // make a pdf of the page
    NSMutableData *data = [[NSMutableData alloc] init];
    UIGraphicsBeginPDFContextToData (data, self.bounds, nil);
    UIGraphicsBeginPDFPage();
    CGContextRef context = UIGraphicsGetCurrentContext();
    [self.layer renderInContext:context];
    UIGraphicsEndPDFContext ();
    
    return data;
}

-(UIImage *)pdfToImage
{
    // Make an image of the page
    UIGraphicsBeginImageContext (self.bounds.size);
    [self.layer renderInContext:UIGraphicsGetCurrentContext()];
    UIImage *image = UIGraphicsGetImageFromCurrentImageContext();
    UIGraphicsEndImageContext();
    return image;
}

/*here is where we are putting the logic that knows the form field api.*/

enum ICPDFViewFieldTypes
{
    kICPDFViewNone,
    
    /*type 1*/
    kICPDFViewPatientNameFirst,
    kICPDFViewPatientNameMiddleInitial,
    kICPDFViewPatientNameLast,
    kICPDFViewPatientNameSuffix,
    kICPDFViewPatientDOB,
    kICPDFViewPatientMRN,
    kICPDFViewPatientVisitID,
    kICPDFViewProcedureName,
    kICPDFViewProviderDoingProcedureName,
    kICPDFViewDateToday,
    kICPDFViewTimeNow,
    kICPDFViewDateAndTimeNow,
    kICPDFViewVideoTitle,
    
    /*type 2*/
    kICPDFViewName,
    kICPDFViewIDNumber,
    kICPDFViewTextField,
    kICPDFViewDate,
    kICPDFViewPhoneNumber,
    kICPDFViewInitials,
    kICPDFViewSignature,
    kICPDFViewCheckbox,
    kICPDFViewRadioButton,
    
    kICPDFViewTextArea,
    kICPDFViewPatientAge,
};


/*
 parse a field in our api, grabbing the int values at the end, for instance radio_1_3 gets 1 and 3 and matches "radio"
 return yes if the parsing worked.
 */

-(BOOL)field:(NSString *)field matches:(NSString *)prefix expectedNumbers:(int)expectedNumbers, ...
{
    insist (self && prefix && expectedNumbers >= 0);
    
    /*if the field doesn't even match the prefix, it's not a match*/
    if (![field hasPrefix:prefix])
        return NO;
    
    /*scan each expected number, if we can't get any, it's not a match*/
    va_list ap;
    va_start(ap, expectedNumbers);
    
    for (int i = 0; i < expectedNumbers; i++)
    {
        /*get the next out argument to return the number in*/
        int *number = va_arg (ap, int *);
        
        /*get a scanner starting after the prefix which ignores our number separator character, _*/
        NSScanner *scanner = [NSScanner scannerWithString:[field substringFromIndex:[prefix length]]];
        insist (scanner);
        scanner.charactersToBeSkipped = [NSCharacterSet characterSetWithCharactersInString:@"_"];
        
        if (![scanner scanInt:number])
            return NO;
    }
    
    va_end (ap);
    
    return YES;
}

/*make the iconsult interactive field API consistent so we can parse it easier.*/

- (NSString *)simplify:(NSString *)field
{
    /*deal with the fact that radio, alone among all fields, doesn't have an underscore before its first number*/
    if ([field hasPrefix:@"radio"])
        field = [NSString stringWithFormat:@"radio_%@", [field substringFromIndex:[@"radio" length]]];
    
    /*anything that has "other_answer" in it is really just a text field. We don't care about the numbers on the end
     of text fields, so just use "1" here.*/
    if ([field hasSuffix:@"other_answer"])
        return @"text_field_1";
    
    return field;
}

/*if the type is a non-auto-fill text field type, and rect is tall, convert the type to multi-line. the height cutoff was
 determined experimentally by looking at some forms.
 */
- (int)multiline:(int)type rect:(CGRect)rect
{
    if (type == kICPDFViewName ||
        type == kICPDFViewIDNumber ||
        type == kICPDFViewPhoneNumber ||
        type == kICPDFViewTextField)
    {
        if (rect.size.height > MIN_TEXT_AREA_HEIGHT)
            return kICPDFViewTextArea;
    }
    return type;
}

/*parse a text field, returning its type, if its required or not, and the group and index numbers*/
-(enum ICPDFViewFieldTypes) parseField:(NSString *)field required:(BOOL *)required group:(int *)group index:(int *)index
{
    insist (self && field && group && index && required);
    *group = *index = 0;
    
    /*fields starting with req_ are required.*/
    if ([field hasPrefix:@"req_"])
    {
        *required = YES;
        field = [field substringFromIndex:[@"req_" length]];
    }
    else
    {
        *required = NO;
    }
    
    /*simply some hard to parse fields*/
    field = [self simplify:field];
    
    /*try and match the field with something in our api. it's first come first serve, so order matters here
     in a few cases.*/
    
    
    if ([self field:field matches:@"patient_name_first" expectedNumbers:1, index])
        return kICPDFViewPatientNameFirst;
    if ([self field:field matches:@"patient_name_middle_initial" expectedNumbers:1, index])
        return kICPDFViewPatientNameMiddleInitial;
    if ([self field:field matches:@"patient_name_last" expectedNumbers:1, index])
        return kICPDFViewPatientNameLast;
    if ([self field:field matches:@"patient_name_suffix" expectedNumbers:1, index])
        return kICPDFViewPatientNameSuffix;
    if ([self field:field matches:@"patient_date_of_birth" expectedNumbers:1, index])
        return kICPDFViewPatientDOB;
    if ([self field:field matches:@"patient_medical_record_number" expectedNumbers:1, index])
        return kICPDFViewPatientMRN;
    if ([self field:field matches:@"patient_visit_ID" expectedNumbers:1, index])
        return kICPDFViewPatientVisitID;
    if ([self field:field matches:@"procedure_name" expectedNumbers:1, index])
        return kICPDFViewProcedureName;
    if ([self field:field matches:@"provider_doing_procedure_name" expectedNumbers:1, index])
        return kICPDFViewProviderDoingProcedureName;
    if ([self field:field matches:@"date_today" expectedNumbers:1, index])
        return kICPDFViewDateToday;
    if ([self field:field matches:@"time_now" expectedNumbers:1, index])
        return kICPDFViewTimeNow;
    if ([self field:field matches:@"date_and_time_now" expectedNumbers:1, index])
        return kICPDFViewDateAndTimeNow;
    if ([self field:field matches:@"video_title" expectedNumbers:1, index])
        return kICPDFViewVideoTitle;
    if ([self field:field matches:@"name" expectedNumbers:1, index])
        return kICPDFViewName;
    if ([self field:field matches:@"ID_number" expectedNumbers:1, index])
        return kICPDFViewIDNumber;
    if ([self field:field matches:@"text_field_multiple_lines" expectedNumbers:1, index])
        return kICPDFViewTextArea;
    if ([self field:field matches:@"text_field" expectedNumbers:1, index])
        return kICPDFViewTextField;
    if ([self field:field matches:@"date" expectedNumbers:1, index])
        return kICPDFViewDate;
    if ([self field:field matches:@"phone_number" expectedNumbers:1, index])
        return kICPDFViewPhoneNumber;
    if ([self field:field matches:@"initials" expectedNumbers:1, index])
        return kICPDFViewInitials;
    if ([self field:field matches:@"signature" expectedNumbers:1, index])
        return kICPDFViewSignature;
    if ([self field:field matches:@"checkbox" expectedNumbers:1, index])
        return kICPDFViewCheckbox;
    if ([self field:field matches:@"radio" expectedNumbers:2, group, index])
        return kICPDFViewRadioButton;
    if ([self field:field matches:@"patient_age" expectedNumbers:1, index])
        return kICPDFViewPatientAge;
    return kICPDFViewNone;
    
    
}

/*get the rect for an annotation. return NO if there was none*/
-(BOOL)getAnnotationRect:(CGRect *)rect page:(CGPDFPageRef)page dict:(CGPDFDictionaryRef)dict rotate:(int)rotate
{
    insist (self && dict && rect);
    
    /*if this annotation dictionary has a rectangle, it's in an array called Rect*/
    CGPDFArrayRef rectArray;
    if (!CGPDFDictionaryGetArray(dict, "Rect", &rectArray))
        return NO;
    
    CGPDFReal coords [4];
    for (int i = 0; i < CGPDFArrayGetCount (rectArray); i++)
    {
        /*get each coordinate object from the rect array*/
        CGPDFObjectRef coordObject;
        if (!CGPDFArrayGetObject (rectArray, i, &coordObject))
            return NO;
        
        /*get the coordinate value itself*/
        if (!CGPDFObjectGetValue(coordObject, kCGPDFObjectTypeReal, &coords [i]))
            return NO;
    }
    
    /*make the CGRect*/
    *rect = CGRectMake (coords [0], coords [1], coords [2], coords [3]);
    
    /*get the size of the page, (in 72 dpi pdf points)*/
    CGRect pageRect = CGRectIntegral(CGPDFPageGetBoxRect(page, kCGPDFMediaBox));
    
    /*do a bunch of matrix magic to convert the rect into UIKit coordinate space, which is upside down from PDF*/
    
    /*
     also correct the annotation rectangle dimensions, they do something truely evil, involving their
     sizes being measured from 0,0, maybe that's some vector stuff
     */
    
    if (rotate == 90 || rotate == 270)
    {
        double t = pageRect.size.height;
        pageRect.size.height = pageRect.size.width;
        pageRect.size.width = t;
        
        rect->size.width -= rect->origin.y;
        rect->size.height -= rect->origin.x;
    }
    else
    {
        rect->size.width -= rect->origin.x;
        rect->size.height -= rect->origin.y;
    }
    /*move the rect down and flip it upside down*/
    CGAffineTransform trans = CGAffineTransformTranslate (CGAffineTransformIdentity, 0, pageRect.size.height);
    trans = CGAffineTransformScale (trans, 1, -1);
    *rect = CGRectApplyAffineTransform(*rect, trans);
    
    return YES;
}

/*get or greate the array of buttons for this group*/

- (NSMutableArray *)radioButtonsForGroup:(int)group
{
    NSString *key = [NSString stringWithFormat:@"%d", group];
    
    NSMutableArray *buttons = [radioButtonGroups valueForKey:key];
    if (!buttons)
    {
        buttons = [[NSMutableArray alloc] init];
        insist (buttons);
        [radioButtonGroups setValue:buttons forKey:key];
    }
    return buttons;
}

-(void)markField:(id)field asSeen:(BOOL)seen
{
    if ([requiredFields containsObject:field])
    {
        if (seen && ![requiredFieldsSeen containsObject:field])
            [requiredFieldsSeen addObject:field];
        else if (!seen && [requiredFieldsSeen containsObject:field])
            [requiredFieldsSeen removeObject:field];
    }
    
    /*hide/show the signature pointer if there is one for this field*/
    if ([signatures containsObject:field])
    {
        UIButton *signature = field;
        insist (signature.tag >= 0 && signature.tag < [signaturePointers count]);
        [[signaturePointers objectAtIndex:signature.tag] setHidden:seen];
    }
}

/*
 if we were able to look up a value, set the label and add it to our view, otherwise
 we couldn't get that data and leave the field blank
 */

-(void)addAutoFillLabel:(UILabel *)label orTextField:(UITextField *)textField value:(NSString *)value required:(BOOL)required
{
    if (value && [(value = [value stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]]) length])
    {
        /*set the label and mark the field as seen*/
        label.text = value;
        [self addSubview:label];
        
        if (required)
            [requiredFields addObject:label];
        [self markField:label asSeen:YES];
    }
    else
    {
        /*we couldn't autofill so the user has to do the work*/
        
        /*actually no:
         "All non-date auto-populated  fields should either be pre-populated or blank (no gray box)."*/
        
        return;
        
        [self addSubview:textField];
        if (required)
            [requiredFields addObject:textField];
    }
}
-(void)addAutoFillLabel:(UILabel *)label orDateButton:(UIButton *)button value:(NSString *)value required:(BOOL)required
{
    if (value && [(value = [value stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]]) length])
    {
        /*set the label and mark the field as seen*/
        label.text = value;
        [self addSubview:label];
        
        if (required)
            [requiredFields addObject:label];
        [self markField:label asSeen:YES];
    }
    else
    {
        /*we couldn't autofill so the user has to do the work*/
        [self addSubview:button];
        [button addTarget:self action:@selector (date:) forControlEvents:UIControlEventTouchUpInside];
        if (required)
            [requiredFields addObject:button];
    }
}

- (void)addSignature:(UIButton *)button required:(BOOL)required
{
    insist (self && button && signatures);
    
    /*add the signature field*/
    button.backgroundColor = signatureBackgroundColor;
    button.tag = [signatures count];
    
    [self addSubview:button];
    if (required)
        [requiredFields addObject:button];
    [button addTarget:self action:@selector (signature:) forControlEvents:UIControlEventTouchUpInside];
    
    /*keep track of the mapping from the pointer to its signature (signatures[pointer.tag] == signature)*/
    insist (signatures);
    [signatures addObject:button];
    
    
    /*make a little pointer button next to the signature field*/
    
    /*make sure to add the pointer button after the signature button so it looks like it is on top*/
    UIButton *pointerButton = [UIButton buttonWithType:UIButtonTypeCustom];
    UIImage*signHereImage = [UIImage imageNamed:@"signhereicon"];
    insist (signHereImage);
    pointerButton.frame = CGRectMake(button.frame.origin.x - signHereImage.size.width/2, button.frame.origin.y - signHereImage.size.height / 2, signHereImage.size.width, signHereImage.size.height);
    [pointerButton setImage:signHereImage forState:UIControlStateNormal];
    [pointerButton setContentMode:UIViewContentModeScaleAspectFit];
    pointerButton.alpha = POINTER_ALPHA;
    [pointerButton addTarget:self action:@selector(pointer:) forControlEvents:UIControlEventTouchUpInside];
    pointerButton.tag = [signaturePointers count]; //use tag to know our index into the signature array
    [self addSubview:pointerButton];
    
    [signaturePointers addObject:pointerButton];
}

/*how many years the patient is old, as a string. if we can't figure it out return the empty string*/
-(NSString *)age
{
    NSDate *dob = patient.birthDate;
    if (!dob)
        return @"";
    
    double seconds = [[NSDate date] timeIntervalSinceDate:dob];
    int years = seconds / 31536000.0;
    return [NSString stringWithFormat:@"%d", years];
}

/*indicate by a red asterix that a button is required. this in practice will
 just be for date fields
 */
-(void)requireButton:(UIButton*)button
{
    insist (self && button);
    [button setTitleColor:[UIColor redColor] forState:UIControlStateNormal];
    [button setTitle:REQUIRED_MARK forState:UIControlStateNormal];
}

/*textViews and textFields both respond to these setters*/
-(void)requireTextField:(id)field
{
    insist (self && field);
    
    [field setText: REQUIRED_MARK];
    [field setTextColor: [UIColor redColor]];
}

/*read the pdf page, converting annotations to buttons and text fields. this is what makes the pdf page interactive.
 the button and text field tags are overloaded for different things.
 
 checkbox tags are 0/1 depending on the checkbox state.
 signature pointer tags are indexes into the signature array.
 text field tags are in sequence to implement next responder behavoir.
 */

-(void)decorate:(CGPDFPageRef)page
{
    insist (self && page);
    insist (fieldBackgroundColor);
    insist (requiredFields && [requiredFields count] == 0);
    insist (requiredFields && [requiredFieldsSeen count] == 0);
    insist (signatures && [signatures count] == 0);
    
    /*
     get the page dictionary, if any. probably should always exist. none of these references are retained since we aren't getting them
     with functions with Create or Copy in their names.
     */
    
    CGPDFDictionaryRef pageDictionary = CGPDFPageGetDictionary(page);
    if (!pageDictionary)
        return;
    
    /*get the annotation array, if any*/
    CGPDFArrayRef annotations;
    if (!CGPDFDictionaryGetArray (pageDictionary, PDF_ANNOTATION_KEY, &annotations))
        return;
    
    /*see if the page is rotated*/
    CGPDFInteger pageRotate = 0;
    CGPDFDictionaryGetInteger (pageDictionary, "Rotate", &pageRotate);
    
    /*step through all the annotations, converting them to text fields and buttons.*/
    
    /*the font for the form fields*/
    UIFont *font = [UIFont fontWithName:TEXT_FONT_NAME size:TEXT_FONT_SIZE];
    insist (font);
    
    /*we are going to tag all the textfields and textviews in order so that the keyboard return button moves through them*/
    int textTag = FIRST_TEXT_TAG;
    
    for (int i = 0; i < CGPDFArrayGetCount (annotations); i++)
    {
        /*get the type and name for the annotation*/
        CGPDFObjectRef dictObject;
        if (!CGPDFArrayGetObject (annotations, i, &dictObject))
            continue;
        
        CGPDFDictionaryRef dict;
        if (!CGPDFObjectGetValue (dictObject,kCGPDFObjectTypeDictionary, &dict))
            continue;
        
        const char *s;
        NSString *typeString = @"";
        if (CGPDFDictionaryGetName(dict, "FT", &s))
            typeString = [NSString stringWithCString:s encoding:NSUTF8StringEncoding];
        
        CGPDFStringRef stringRef;
        NSString *fieldName = @"";
        if (CGPDFDictionaryGetString(dict, "T", &stringRef))
        {
            char *s = (char *) CGPDFStringGetBytePtr(stringRef);
            insist (s);
            fieldName = [NSString stringWithCString:s encoding:NSUTF8StringEncoding];
        }
        
        /*there are 4 annotation types: Tx, Ch, Btn, and Sig, we only care about text field and signature*/
        if (![typeString isEqualToString:@"Tx"] && ![typeString isEqualToString:@"Sig"])
            continue;
        
        /*get the rectangle, in UIView coordinates, for the annotation*/
        CGRect rect;
        if (![self getAnnotationRect:&rect page:page dict:dict rotate:pageRotate])
            continue;
        
        
        int index, group;
        BOOL required;
        int type = [self parseField:fieldName required:&required group:&group index:&index ];
        //NSLog (@"%@ type is %d required is %d group is %d index is %d, rect height is %lf", fieldName, type, required, group, index, rect.size.height);
        
        /*if we have a non auto-fill text field, and it's tall, make it into a text area type*/
        type = [self multiline:type rect:rect];
        
        /*
         make the UIKit types we might need for this field, we might not use any of them in which case
         they're never added to the view and they get released when we go out of scope.
         
         buttons are for signatures, initials, or dates that have to be entered through a picker
         
         labels are for fields we can pre-fill out, like patient name or DOB.
         
         textFields and textViews are for stuff the user has to fill out himself.
         
         required textFields and views are pre-set to contain red asterixes.
         same as buttons that are not signature/initial buttons.
         */
        
        UIButton *button = [UIButton buttonWithType:UIButtonTypeCustom];
        insist (button);
        button.frame = rect;
        button.titleLabel.font = font;
        button.backgroundColor = fieldBackgroundColor;
        [button setTitleColor:[UIColor blackColor] forState:UIControlStateNormal];
        button.titleLabel.adjustsFontSizeToFitWidth = YES;
        
        if ([button.titleLabel respondsToSelector:@selector(setMinimumScaleFactor:)])
            button.titleLabel.minimumScaleFactor = LABEL_MIN_SCALE_FACTOR;
        else
            button.titleLabel.minimumFontSize = LABEL_MIN_SCALE_FACTOR * TEXT_FONT_SIZE;

        UILabel *label = [[UILabel alloc] initWithFrame:rect];
        insist (label);
        label.font = font;
        label.backgroundColor = [UIColor clearColor];
        label.adjustsFontSizeToFitWidth = YES;
        if ([label respondsToSelector:@selector(setMinimumScaleFactor:)])
            label.minimumScaleFactor = LABEL_MIN_SCALE_FACTOR;
        else
            label.minimumFontSize = LABEL_MIN_SCALE_FACTOR * TEXT_FONT_SIZE;
        
        UITextField *textField = [[UITextField alloc] initWithFrame:rect];
        insist (textField);
        textField.font = font;
        textField.backgroundColor = fieldBackgroundColor;
        textField.delegate = self;
        
        UITextView *textView = [[UITextView alloc] initWithFrame:rect];
        insist (textView);
        textView.font = font;
        textView.backgroundColor = fieldBackgroundColor;
        textView.delegate = self;
        
        /*if the field is required, mark the text fields as required*/
        if (required)
        {
            [self requireTextField:textField];
            [self requireTextField:textView];
        }
        /*place the UIKIt thing on top of the PDF annotation*/
        switch (type)
        {
                /*type 1, autofill*/
            case kICPDFViewNone:
                break;
            case kICPDFViewPatientNameFirst:
                [self addAutoFillLabel:label orTextField:textField value:patient.firstName required:required];
                break;
            case kICPDFViewPatientNameMiddleInitial:
                [self addAutoFillLabel:label orTextField:textField value:patient.middleInitial required:required];
                break;
            case kICPDFViewPatientNameLast:
                [self addAutoFillLabel:label orTextField:textField value:patient.lastName required:required];
                break;
            case kICPDFViewPatientNameSuffix:
                [self addAutoFillLabel:label orTextField:textField value:patient.suffix required:required];
                break;
            case kICPDFViewPatientDOB:
                if (required)
                    [self requireButton:button];
                [self addAutoFillLabel:label orDateButton:button value:patient.birthDateShortFormat required:required];
                break;
            case kICPDFViewPatientMRN:
                [self addAutoFillLabel:label orTextField:textField value:patient.emrNumber required:required];
                break;
            case kICPDFViewPatientVisitID:
                [self addAutoFillLabel:label orTextField:textField value:consult.patientVisit.name required:required];
                break;
            case kICPDFViewProcedureName:
                [self addAutoFillLabel:label orTextField:textField value:consult.presentation.name required:required];
                break;
            case kICPDFViewProviderDoingProcedureName:
                [self addAutoFillLabel:label orTextField:textField value:consult.provider.professionalName required:required];
                break;
            case kICPDFViewDateToday:
                [self addSubview:button];
                if (required)
                {
                    [requiredFields addObject:button];
                    [self requireButton:button];
                }
                [button addTarget:self action:@selector (dateNow:) forControlEvents:UIControlEventTouchUpInside];
                break;
            case kICPDFViewTimeNow:
                [self addSubview:button];
                if (required)
                {
                    [requiredFields addObject:button];
                    [self requireButton:button];
                }
                [button addTarget:self action:@selector (timeNow:) forControlEvents:UIControlEventTouchUpInside];
                break;
            case kICPDFViewDateAndTimeNow:
                [self addSubview:button];
                if (required)
                {
                    [requiredFields addObject:button];
                    [self requireButton:button];
                }
                [button addTarget:self action:@selector (dateAndTimeNow:) forControlEvents:UIControlEventTouchUpInside];
                break;
            case kICPDFViewVideoTitle:
                [self addAutoFillLabel:label orTextField:textField value:consult.provider.professionalName required:required];
                break;
                /*type 2, no autofill*/
            case kICPDFViewName:
            case kICPDFViewIDNumber:
            case kICPDFViewPhoneNumber:
            case kICPDFViewTextField:
                [self addSubview:textField];
                if (required)
                    [requiredFields addObject:textField];
                textField.tag = textTag++;
                break;
            case kICPDFViewTextArea:
                [self addSubview:textView];
                if (required)
                    [requiredFields addObject:textView];
                textView.tag = textTag++;
                break;
            case kICPDFViewInitials:
            case kICPDFViewSignature:
                [self addSignature:button required:required];
                break;
            case kICPDFViewDate:
                [self addSubview:button];
                if (required)
                {
                    [requiredFields addObject:button];
                    [self requireButton:button];
                }
                [button addTarget:self action:@selector (date:) forControlEvents:UIControlEventTouchUpInside];
                break;
            case kICPDFViewCheckbox:
                [self addSubview:button];
                if (required)
                    [requiredFields addObject:button];
                button.tag = 0; //means unchecked
                [button addTarget:self action:@selector (checkbox:) forControlEvents:UIControlEventTouchUpInside];
                break;
            case kICPDFViewRadioButton:
                [self addSubview:button];
                if (required)
                    [requiredFields addObject:button];
                [button addTarget:self action:@selector (radioButton:) forControlEvents:UIControlEventTouchUpInside];
                
                /*use the tag field to remember the button's group, and add the button to its group array*/
                button.tag = group;
                [[self radioButtonsForGroup:group] addObject:button];
                break;
            case kICPDFViewPatientAge:
                [self addAutoFillLabel:label orDateButton:button value:[self age] required:required];
                break;
            default:
                insist (0);
                break;
        }
    }
}

/*
 these all callback to the delegate to do whatever UI stuff he wants to get us our data. for instance
 put up a signature box or date picker. The delegate then is supposed to give us the data in setSignature:forButton
 or setDate:forButton.
 */

-(void)signature:(id)sender
{
    insist (self && sender);
    [delegate pdfViewDidTapSignature:self button:sender];
}
-(void)date:(id)sender
{
    insist (self && sender);
    [delegate pdfViewDidTapDate:self button:sender maxDate:nil];
}

/*forward the action to the corresponding signature button*/
-(void)pointer:(UIButton *)button
{
    insist (self && signatures && button);
    insist (button.tag >= 0 && button.tag < [signatures count]);
    [self signature:[signatures objectAtIndex:button.tag]];
}

/*mark the button as checked*/

-(void)checkbox:(UIButton *)button
{
    insist (self && button);
    [button setTitleColor:[UIColor blackColor] forState:UIControlStateNormal];
    
    /*toggle the state we are keeping, in "tag", of the button being checked or not*/
    button.tag = button.tag ? 0 : 1;
    [button setTitle:button.tag ? CHECKBOX_STRING : @"" forState:UIControlStateNormal];
    button.titleLabel.font = [UIFont fontWithName:CHECKBOX_FONT_NAME size:CHECKBOX_FONT_SIZE];
    
    /*almost certainly nonsense but we shouldn't care*/
    [self markField:button asSeen:YES];
}

-(void)radioButton:(UIButton *)button
{
    insist (self && button);
    
    /*get the buttons in this button's group*/
    NSArray *buttons = [self radioButtonsForGroup:button.tag];
    insist (buttons);
    
    /*
     uncheck all the buttons in the group. also if any button in the group is required mark is as seen.
     in a perfectly sane world if a radio button group is required our spec should say that all the
     groups radio buttons were listed as required in the field names. rather than test to make sure
     that this was done right (since how do we handle the error?) just do the right thing here.
     */
    
    for (UIButton *b in buttons)
    {
        [b setTitle:@"" forState:UIControlStateNormal];
        [self markField:button asSeen:YES];
    }
    
    /*mark the newly selected button as checked, with a small black X*/
    [button setTitleColor:[UIColor blackColor] forState:UIControlStateNormal];
    [button setTitle:CHECKBOX_STRING forState:UIControlStateNormal];
    button.titleLabel.font = [UIFont fontWithName:CHECKBOX_FONT_NAME size:CHECKBOX_FONT_SIZE];
}

-(id)initWithPage:(CGPDFPageRef)page delegate:(id <ICPDFViewDelegate>)aDelegate consult:(ICConsult *)aConsult patient:(ICPatient*)aPatient videoTitle:(NSString*)aVideoTitle;
{
    insist (page && aDelegate);
    
    /*get the size of the page, (in 72 dpi pdf points)*/
    CGRect pageRect = CGRectIntegral(CGPDFPageGetBoxRect(page, kCGPDFMediaBox));

    /*size ourself to be as big as the page*/
    self = [super initWithFrame:pageRect];
    if (self)
    {
        delegate = aDelegate;
        
        /*make the view that will render the PDF page undeneath all the buttons and text fields we are going to add.*/
        ICPDFRenderingView *view = [[ICPDFRenderingView alloc] initWithFrame:self.frame page:page];
        [self addSubview:view];
        
        /*
         we keep track of what fields are required, and also what required fields the user has edited (seen).
         in the case of buttons once a required field has been set, then it will always be added to the seen
         list. in the case of text fields, if the user goes back and types in nothing but whitespace, then
         the field will be recorded as needing to be filled out again.
         
         when the seen list has the same number of items as the required list, the page is known to be completed.
         */
        
        requiredFields = [[NSMutableArray alloc] init];
        requiredFieldsSeen = [[NSMutableArray alloc] init];
        signatureButtons = [[NSMutableArray alloc] init];
        radioButtons = [[NSMutableArray alloc] init];
        
        /*we keep track of groups of radio buttons in a dictionary, keyed off of the group number, of arrays of buttons*/
        radioButtonGroups = [[NSMutableDictionary alloc] init];
        insist (radioButtonGroups);
        
        /*
         these two arrays are in the same order, and aside from letting us deal with the signature pointers, for when
         we animate them, they also let us map between signature pointers and their corresponding signatures.
         */
        signatures = [[NSMutableArray alloc] init];
        signaturePointers = [[NSMutableArray alloc] init];
        
        /*we use this for autofill. consult and videoTitle can each be nil, it's ok if patient == patient*/
        consult = aConsult;
        patient = aPatient;
        videoTitle = aVideoTitle;
        
        /*make the color we use to color the pdf form fields*/
        fieldBackgroundColor = [UIColor colorWithRed:204.0/255.0 green:204.0/255.0 blue:204.0/255.0 alpha:.4];
        insist (fieldBackgroundColor);
        
        signatureBackgroundColor = [UIColor colorWithRed:161.0/255.0 green:207.0/255.0 blue:234.0/255.0 alpha:.4];
        
        /*overlay UIKit controls on top of the pdf*/
       [self decorate:page];
    }
    return self;
}


/*mark a field as completed*/
-(void)finishButton:(UIButton *)button
{
    insist (self && requiredFields && button);
    
    button.backgroundColor = [UIColor clearColor];
    button.enabled = FALSE;
    [self markField:button asSeen:YES];
}

/*this fills in the field with the current time when the user taps it*/
-(void)setNow:(UIButton *)button withFormat:(NSString*)format
{
    insist (self && button && format && [format length]);
    NSDateFormatter *formatter = [[NSDateFormatter alloc] init];
    [formatter setDateFormat:format];
    insist (formatter);
    [button setTitle:[formatter stringFromDate:[NSDate date]] forState:UIControlStateNormal];
    [button setTitleColor:[UIColor blackColor] forState:UIControlStateNormal];
    
    [self finishButton:button];
}
-(void)dateNow:(UIButton *)button
{
    [self setNow:button withFormat:DATE_FORMAT];
}
-(void)timeNow:(UIButton *)button
{
    [self setNow:button withFormat:TIME_FORMAT];
}
-(void)dateAndTimeNow:(UIButton *)button
{
    [self setNow:button withFormat:DATE_AND_TIME_FORMAT];
}

/* set the image of a signature button with a signature and complete the field */
-(void)setSignature:(UIImage *)image forButton:(UIButton *)button
{
    insist (self);
    insist (image && button);
    
    [button setImage:image forState:UIControlStateNormal];
    [self finishButton:button];
}

/*set the title of a date button with a date and complete the field*/
-(void)setDate:(NSDate *)date forButton:(UIButton *)button
{
    insist (self && requiredFields);
    insist (date && button);
    
    NSDateFormatter *dateFormat = [[NSDateFormatter alloc] init];
    [dateFormat setDateFormat:DATE_FORMAT];
    NSString *dateString = [dateFormat stringFromDate:date];
    [button setTitleColor:[UIColor blackColor] forState:UIControlStateNormal];
    
    [button setTitle:dateString forState:UIControlStateNormal];
    [self finishButton:button];
}

/*return how many fields are not yet completed*/
-(NSInteger)numRequiredFields
{
    insist (self && requiredFields);
    
    return [requiredFields count] - [requiredFieldsSeen count];
}

/*
 if a text field is required, mark it as fullfilled or not depending on if text is non empty or not. this is a helper
 method for the text field delegate stuff. also make sure an empty required text field has a red * in it.
 */
-(void)seeTextFieldOrView:(id)textFieldOrView text:(NSString *)text
{
    insist (self && text && textFieldOrView);
    insist ([textFieldOrView isKindOfClass:[UITextView class]] || [textFieldOrView isKindOfClass:[UITextField class]]);
    
    /*trim the string, first of whitespace*/
    NSString*s = [text stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    
    /*if it's just the asterix, trim that too.*/
    if ([s isEqualToString:REQUIRED_MARK])
        s = @"";
    
    BOOL nonEmpty = [s length] != 0;
    
    /*color the field grey if it's empty, clear otherwise (meaning it was filled in)*/
    [textFieldOrView setBackgroundColor:nonEmpty ? [UIColor clearColor] : fieldBackgroundColor];
    
    /*mark the field as seen/unseen depending on if it's empty or not. this will do our required field bookkeeping*/
    [self markField:textFieldOrView asSeen:nonEmpty];
    
    /*if it's a required field, and it's empty, put the red asterix back in*/
    if ([requiredFields containsObject:textFieldOrView] && !nonEmpty)
        [self requireTextField:textFieldOrView];
}


-(UIView*)activeField
{
    return activeField;
}

#pragma mark - UITextFieldDelegate and UITextViewDelegate methods

/*
 for text fields we make sure return moves to the next text field, if appropriate. in both text fields
 and text views we also keep track of if a required field has had stuff typed in it or not.
 */


-(void)textViewDidEndEditing:(UITextView *)textView
{
    insist (self && textView);
    [self seeTextFieldOrView:textView text:textView.text];
}


-(void)textFieldDidBeginEditing:(UITextField *)textField
{
    /*clear anything existing, for instance a red asterix on a required field*/
    textField.text = @"";
    textField.textColor = [UIColor blackColor];
    [self markField:textField asSeen:NO];
    
    /*
     we keep track of the active text field in case the code that uses this class wants to make sure
     that the text field is visible when the keyboard comes up. it's either a text field or a text view.
     */
    
    activeField = textField;
}
-(void)textViewDidBeginEditing:(UITextView *)textView
{
    /*clear anything existing, for instance a red asterix on a required field*/
    textView.text = @"";
    textView.textColor = [UIColor blackColor];
    [self markField:textView asSeen:NO];
    activeField = textView;
}

-(void)textFieldDidEndEditing:(UITextField *)textField
{
    insist (self && textField);
    [self seeTextFieldOrView:textField text:textField.text];
}

- (BOOL)textFieldShouldReturn:(UITextField *)textField
{
    insist (self && textField);
    
    /*if there's a next responder attach the keyboard to it, otherwise drop the keyboard*/
    UIResponder *nextResponder = [textField.superview viewWithTag:textField.tag + 1];
    if (nextResponder)
        [nextResponder becomeFirstResponder];
    else
        [textField resignFirstResponder];
    return YES;
}


@end
