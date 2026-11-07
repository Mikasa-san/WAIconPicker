//
//  WAIconPicker 2.0
//  Modern in-app icon picker for WhatsApp (grid layout, live preview,
//  haptics, sheet presentation, English / Arabic).
//

#import <UIKit/UIKit.h>
#import <Foundation/Foundation.h>
#import <objc/runtime.h>

#pragma mark - Interfaces

@interface WASettingsViewController : UIViewController
- (void)openWAIconPicker;
@end

@interface WAIconPickerViewController : UIViewController <UICollectionViewDataSource, UICollectionViewDelegate>
@end

#pragma mark - Constants

static NSString * const kWAIPButtonIdentifier = @"WAIconPickerButton";

typedef NS_ENUM(NSInteger, WAIPSection) {
	WAIPSectionHero = 0,
	WAIPSectionIcons,
	WAIPSectionCount
};

static UIColor *WAIPAccentColor(void) {
	// WhatsApp brand green, slightly deeper in light mode for contrast.
	return [UIColor colorWithDynamicProvider:^UIColor *(UITraitCollection *traits) {
		return traits.userInterfaceStyle == UIUserInterfaceStyleDark
			? [UIColor colorWithRed:0.15 green:0.83 blue:0.40 alpha:1.0]
			: [UIColor colorWithRed:0.00 green:0.66 blue:0.32 alpha:1.0];
	}];
}

#pragma mark - Localization (English / Arabic)

static BOOL WAIPIsArabic(void) {
	static BOOL arabic;
	static dispatch_once_t onceToken;
	dispatch_once(&onceToken, ^{
		NSString *lang = NSBundle.mainBundle.preferredLocalizations.firstObject ?: NSLocale.preferredLanguages.firstObject;
		arabic = [lang hasPrefix:@"ar"];
	});
	return arabic;
}

#define WAIPL(en, ar) (WAIPIsArabic() ? (ar) : (en))

#pragma mark - Saved icon choice

static NSString * const kWAIPSavedIconKey = @"com.hitori.waiconpicker.selectedIcon";
static NSString * const kWAIPDefaultMarker = @"__default__";

// YES only while the picker itself is calling setAlternateIconName.
static BOOL gWAIPIsOwnChange = NO;
// Calls from WhatsApp this soon after launch are treated as "restore my old icon" and blocked.
static const CFTimeInterval kWAIPLaunchGuardSeconds = 20.0;
static CFAbsoluteTime gWAIPLaunchTime = 0;

static BOOL WAIPHasSavedChoice(void) {
	return [NSUserDefaults.standardUserDefaults stringForKey:kWAIPSavedIconKey] != nil;
}

// nil = default icon. Only meaningful when WAIPHasSavedChoice() is YES.
static NSString *WAIPSavedAlternateName(void) {
	NSString *saved = [NSUserDefaults.standardUserDefaults stringForKey:kWAIPSavedIconKey];
	return [saved isEqualToString:kWAIPDefaultMarker] ? nil : saved;
}

static void WAIPSaveAlternateName(NSString *name) {
	[NSUserDefaults.standardUserDefaults setObject:(name.length ? name : kWAIPDefaultMarker) forKey:kWAIPSavedIconKey];
	[NSUserDefaults.standardUserDefaults synchronize];
}

// What the picker should show as the current icon.
static NSString *WAIPResolvedCurrentAlternateName(void) {
	NSString *system = UIApplication.sharedApplication.alternateIconName;
	if (system.length) {
		// The system knows for sure — keep our copy in sync with it.
		if (![system isEqualToString:WAIPSavedAlternateName()]) WAIPSaveAlternateName(system);
		return system;
	}
	// Sideloaded/injected apps often report nil even after a change: trust our saved choice.
	return WAIPHasSavedChoice() ? WAIPSavedAlternateName() : nil;
}

#pragma mark - Icon model

@interface WAIPIcon : NSObject
@property (nonatomic, copy, nullable) NSString *alternateName; // nil = primary icon
@property (nonatomic, copy) NSString *displayName;
@property (nonatomic, copy) NSArray<NSString *> *candidateImageNames;
@property (nonatomic, readonly, nullable) UIImage *previewImage;
@end

@implementation WAIPIcon {
	UIImage *_cachedPreview;
	BOOL _didLoadPreview;
}

- (UIImage *)previewImage {
	if (_didLoadPreview) return _cachedPreview;
	_didLoadPreview = YES;

	for (NSString *name in self.candidateImageNames) {
		UIImage *image = [UIImage imageNamed:name];
		if (image) { _cachedPreview = image; break; }
	}

	return _cachedPreview;
}

@end

static NSString *WAIPDisplayNameForIconName(NSString *name) {
	// "AppIcon-07" -> "Icon 7" / "الأيقونة 7"
	NSRegularExpression *regex = [NSRegularExpression regularExpressionWithPattern:@"(\\d+)$" options:0 error:nil];
	NSTextCheckingResult *match = [regex firstMatchInString:name options:0 range:NSMakeRange(0, name.length)];

	if (match) {
		NSInteger number = [[name substringWithRange:[match rangeAtIndex:1]] integerValue];
		return [NSString stringWithFormat:WAIPL(@"Icon %ld", @"الأيقونة %ld"), (long)number];
	}

	NSString *pretty = [name stringByReplacingOccurrencesOfString:@"AppIcon" withString:@""];
	pretty = [pretty stringByTrimmingCharactersInSet:[NSCharacterSet characterSetWithCharactersInString:@"-_ "]];
	return pretty.length ? pretty : name;
}

static NSArray<NSString *> *WAIPImageCandidates(NSString *iconName, NSDictionary *entry) {
	NSMutableArray<NSString *> *names = [NSMutableArray array];

	NSString *assetName = entry[@"CFBundleIconName"];
	if ([assetName isKindOfClass:NSString.class]) [names addObject:assetName];

	NSArray *files = entry[@"CFBundleIconFiles"];
	if ([files isKindOfClass:NSArray.class]) {
		for (NSString *file in files.reverseObjectEnumerator) {
			if ([file isKindOfClass:NSString.class]) [names addObject:file];
		}
	}

	if (iconName.length) {
		[names addObject:[NSString stringWithFormat:@"%@@3x", iconName]];
		[names addObject:[NSString stringWithFormat:@"%@@2x", iconName]];
		[names addObject:[NSString stringWithFormat:@"%@60x60", iconName]];
		[names addObject:iconName];
	}

	return names;
}

static NSArray<WAIPIcon *> *WAIPLoadIcons(void) {
	static NSArray<WAIPIcon *> *icons;
	static dispatch_once_t onceToken;

	dispatch_once(&onceToken, ^{
		NSDictionary *info = NSBundle.mainBundle.infoDictionary;
		NSString *iconsKey = UIDevice.currentDevice.userInterfaceIdiom == UIUserInterfaceIdiomPad ? @"CFBundleIcons~ipad" : @"CFBundleIcons";
		NSDictionary *bundleIcons = info[iconsKey] ?: info[@"CFBundleIcons"];

		NSMutableArray<WAIPIcon *> *result = [NSMutableArray array];

		// Primary icon
		WAIPIcon *primary = [WAIPIcon new];
		primary.alternateName = nil;
		primary.displayName = WAIPL(@"Default", @"الافتراضية");
		NSMutableArray *primaryCandidates = [WAIPImageCandidates(@"", bundleIcons[@"CFBundlePrimaryIcon"]) mutableCopy];
		[primaryCandidates addObjectsFromArray:@[@"AppIcon60x60", @"AppIcon"]];
		primary.candidateImageNames = primaryCandidates;
		[result addObject:primary];

		// Alternate icons — discovered from Info.plist so new WhatsApp icons appear automatically.
		NSDictionary *alternates = bundleIcons[@"CFBundleAlternateIcons"];
		NSArray<NSString *> *names = nil;

		if ([alternates isKindOfClass:NSDictionary.class] && alternates.count) {
			names = [alternates.allKeys sortedArrayUsingSelector:@selector(localizedStandardCompare:)];
		} else {
			// Fallback to the list the original tweak shipped with.
			NSMutableArray *fallback = [NSMutableArray array];
			for (NSInteger i = 1; i <= 14; i++) [fallback addObject:[NSString stringWithFormat:@"AppIcon-%02ld", (long)i]];
			names = fallback;
			alternates = nil;
		}

		for (NSString *name in names) {
			WAIPIcon *icon = [WAIPIcon new];
			icon.alternateName = name;
			icon.displayName = WAIPDisplayNameForIconName(name);
			NSDictionary *entry = [alternates[name] isKindOfClass:NSDictionary.class] ? alternates[name] : nil;
			icon.candidateImageNames = WAIPImageCandidates(name, entry);
			[result addObject:icon];
		}

		icons = result;
	});

	return icons;
}

#pragma mark - Visual helpers

static void WAIPApplyIconCorners(UIView *view, CGFloat size) {
	view.layer.cornerRadius = size * 0.2237; // iOS app icon squircle ratio
	view.layer.cornerCurve = kCACornerCurveContinuous;
	view.clipsToBounds = YES;
}

static UIImage *WAIPPlaceholderImage(void) {
	UIImageSymbolConfiguration *config = [UIImageSymbolConfiguration configurationWithPointSize:28 weight:UIImageSymbolWeightMedium];
	return [[UIImage systemImageNamed:@"app.dashed" withConfiguration:config] imageWithTintColor:UIColor.tertiaryLabelColor renderingMode:UIImageRenderingModeAlwaysOriginal];
}

#pragma mark - Hero (current icon) cell

@interface WAIPHeroCell : UICollectionViewCell
@property (nonatomic, strong) UIView *cardView;
@property (nonatomic, strong) UIView *iconShadow;
@property (nonatomic, strong) UIImageView *iconView;
@property (nonatomic, strong) UILabel *captionLabel;
@property (nonatomic, strong) UILabel *titleLabel;
@property (nonatomic, strong) UILabel *subtitleLabel;
- (void)configureWithIcon:(WAIPIcon *)icon totalCount:(NSUInteger)count animated:(BOOL)animated;
@end

@implementation WAIPHeroCell

- (instancetype)initWithFrame:(CGRect)frame {
	self = [super initWithFrame:frame];
	if (!self) return nil;

	_cardView = [UIView new];
	_cardView.backgroundColor = UIColor.secondarySystemGroupedBackgroundColor;
	_cardView.translatesAutoresizingMaskIntoConstraints = NO;
	_cardView.layer.cornerRadius = 26.0;
	_cardView.layer.cornerCurve = kCACornerCurveContinuous;
	_cardView.clipsToBounds = YES;
	[self.contentView addSubview:_cardView];

	UIView *tint = [UIView new];
	tint.translatesAutoresizingMaskIntoConstraints = NO;
	tint.backgroundColor = [WAIPAccentColor() colorWithAlphaComponent:0.10];
	[_cardView addSubview:tint];

	CGFloat iconSize = 76.0;

	_iconShadow = [UIView new];
	_iconShadow.translatesAutoresizingMaskIntoConstraints = NO;
	_iconShadow.layer.shadowColor = UIColor.blackColor.CGColor;
	_iconShadow.layer.shadowOpacity = 0.22;
	_iconShadow.layer.shadowRadius = 10.0;
	_iconShadow.layer.shadowOffset = CGSizeMake(0, 5);
	[_cardView addSubview:_iconShadow];

	_iconView = [UIImageView new];
	_iconView.translatesAutoresizingMaskIntoConstraints = NO;
	_iconView.contentMode = UIViewContentModeScaleAspectFill;
	_iconView.backgroundColor = UIColor.tertiarySystemFillColor;
	WAIPApplyIconCorners(_iconView, iconSize);
	[_iconShadow addSubview:_iconView];

	_captionLabel = [UILabel new];
	_captionLabel.font = [UIFont preferredFontForTextStyle:UIFontTextStyleCaption1];
	_captionLabel.textColor = WAIPAccentColor();
	_captionLabel.adjustsFontForContentSizeCategory = YES;

	UIFontDescriptor *titleDescriptor = [[UIFontDescriptor preferredFontDescriptorWithTextStyle:UIFontTextStyleTitle2] fontDescriptorWithSymbolicTraits:UIFontDescriptorTraitBold];
	_titleLabel = [UILabel new];
	_titleLabel.font = [UIFont fontWithDescriptor:titleDescriptor size:0];
	_titleLabel.textColor = UIColor.labelColor;
	_titleLabel.adjustsFontForContentSizeCategory = YES;

	_subtitleLabel = [UILabel new];
	_subtitleLabel.font = [UIFont preferredFontForTextStyle:UIFontTextStyleSubheadline];
	_subtitleLabel.textColor = UIColor.secondaryLabelColor;
	_subtitleLabel.numberOfLines = 2;
	_subtitleLabel.adjustsFontForContentSizeCategory = YES;

	UIStackView *labels = [[UIStackView alloc] initWithArrangedSubviews:@[_captionLabel, _titleLabel, _subtitleLabel]];
	labels.axis = UILayoutConstraintAxisVertical;
	labels.spacing = 2.0;
	[labels setCustomSpacing:6.0 afterView:_titleLabel];
	labels.translatesAutoresizingMaskIntoConstraints = NO;
	[_cardView addSubview:labels];

	[NSLayoutConstraint activateConstraints:@[
		[_cardView.topAnchor constraintEqualToAnchor:self.contentView.topAnchor],
		[_cardView.bottomAnchor constraintEqualToAnchor:self.contentView.bottomAnchor],
		[_cardView.leadingAnchor constraintEqualToAnchor:self.contentView.leadingAnchor],
		[_cardView.trailingAnchor constraintEqualToAnchor:self.contentView.trailingAnchor],

		[tint.topAnchor constraintEqualToAnchor:_cardView.topAnchor],
		[tint.bottomAnchor constraintEqualToAnchor:_cardView.bottomAnchor],
		[tint.leadingAnchor constraintEqualToAnchor:_cardView.leadingAnchor],
		[tint.trailingAnchor constraintEqualToAnchor:_cardView.trailingAnchor],

		[_iconShadow.leadingAnchor constraintEqualToAnchor:_cardView.leadingAnchor constant:18.0],
		[_iconShadow.topAnchor constraintGreaterThanOrEqualToAnchor:_cardView.topAnchor constant:18.0],
		[_iconShadow.centerYAnchor constraintEqualToAnchor:_cardView.centerYAnchor],
		[_iconShadow.widthAnchor constraintEqualToConstant:iconSize],
		[_iconShadow.heightAnchor constraintEqualToConstant:iconSize],

		[_iconView.topAnchor constraintEqualToAnchor:_iconShadow.topAnchor],
		[_iconView.bottomAnchor constraintEqualToAnchor:_iconShadow.bottomAnchor],
		[_iconView.leadingAnchor constraintEqualToAnchor:_iconShadow.leadingAnchor],
		[_iconView.trailingAnchor constraintEqualToAnchor:_iconShadow.trailingAnchor],

		[labels.leadingAnchor constraintEqualToAnchor:_iconShadow.trailingAnchor constant:16.0],
		[labels.trailingAnchor constraintEqualToAnchor:_cardView.trailingAnchor constant:-18.0],
		[labels.centerYAnchor constraintEqualToAnchor:_cardView.centerYAnchor],
		[labels.topAnchor constraintGreaterThanOrEqualToAnchor:_cardView.topAnchor constant:18.0],
	]];

	self.isAccessibilityElement = YES;
	self.accessibilityTraits = UIAccessibilityTraitHeader;

	return self;
}

- (void)configureWithIcon:(WAIPIcon *)icon totalCount:(NSUInteger)count animated:(BOOL)animated {
	void (^apply)(void) = ^{
		self.iconView.image = icon.previewImage ?: WAIPPlaceholderImage();
		self.iconView.contentMode = icon.previewImage ? UIViewContentModeScaleAspectFill : UIViewContentModeCenter;
		self.captionLabel.text = WAIPL(@"CURRENT ICON", @"الأيقونة الحالية");
		self.titleLabel.text = icon.displayName;
		self.subtitleLabel.text = [NSString stringWithFormat:WAIPL(@"%lu icons available · pick one below", @"%lu أيقونة متاحة · اختر واحدة من الأسفل"), (unsigned long)count];
	};

	self.accessibilityLabel = [NSString stringWithFormat:@"%@, %@", WAIPL(@"Current icon", @"الأيقونة الحالية"), icon.displayName];

	if (!animated) { apply(); return; }

	[UIView transitionWithView:self.cardView duration:0.35 options:UIViewAnimationOptionTransitionCrossDissolve | UIViewAnimationOptionAllowUserInteraction animations:apply completion:nil];

	self.iconShadow.transform = CGAffineTransformMakeScale(0.82, 0.82);
	[UIView animateWithDuration:0.55 delay:0 usingSpringWithDamping:0.55 initialSpringVelocity:0.8 options:UIViewAnimationOptionAllowUserInteraction animations:^{
		self.iconShadow.transform = CGAffineTransformIdentity;
	} completion:nil];
}

@end

#pragma mark - Grid icon cell

@interface WAIPIconCell : UICollectionViewCell
@property (nonatomic, strong) UIView *ringView;
@property (nonatomic, strong) UIImageView *iconView;
@property (nonatomic, strong) UIImageView *checkView;
@property (nonatomic, strong) UILabel *nameLabel;
@property (nonatomic, assign) BOOL isCurrent;
- (void)configureWithIcon:(WAIPIcon *)icon current:(BOOL)current animated:(BOOL)animated;
@end

@implementation WAIPIconCell

static const CGFloat kWAIPGridIconSize = 64.0;

- (instancetype)initWithFrame:(CGRect)frame {
	self = [super initWithFrame:frame];
	if (!self) return nil;

	CGFloat ringPadding = 4.0;
	CGFloat ringSize = kWAIPGridIconSize + ringPadding * 2.0;

	_ringView = [UIView new];
	_ringView.translatesAutoresizingMaskIntoConstraints = NO;
	_ringView.layer.cornerRadius = ringSize * 0.2237 + 1.0;
	_ringView.layer.cornerCurve = kCACornerCurveContinuous;
	_ringView.layer.borderWidth = 2.5;
	_ringView.layer.borderColor = UIColor.clearColor.CGColor;
	[self.contentView addSubview:_ringView];

	_iconView = [UIImageView new];
	_iconView.translatesAutoresizingMaskIntoConstraints = NO;
	_iconView.contentMode = UIViewContentModeScaleAspectFill;
	_iconView.backgroundColor = UIColor.tertiarySystemFillColor;
	WAIPApplyIconCorners(_iconView, kWAIPGridIconSize);
	[_ringView addSubview:_iconView];

	UIImageSymbolConfiguration *checkConfig = [UIImageSymbolConfiguration configurationWithPointSize:20 weight:UIImageSymbolWeightBold];
	_checkView = [[UIImageView alloc] initWithImage:[UIImage systemImageNamed:@"checkmark.circle.fill" withConfiguration:checkConfig]];
	_checkView.translatesAutoresizingMaskIntoConstraints = NO;
	_checkView.tintColor = WAIPAccentColor();
	_checkView.backgroundColor = UIColor.systemBackgroundColor;
	_checkView.layer.cornerRadius = 11.0;
	_checkView.clipsToBounds = YES;
	_checkView.alpha = 0.0;
	[self.contentView addSubview:_checkView];

	_nameLabel = [UILabel new];
	_nameLabel.translatesAutoresizingMaskIntoConstraints = NO;
	_nameLabel.font = [UIFont preferredFontForTextStyle:UIFontTextStyleFootnote];
	_nameLabel.adjustsFontForContentSizeCategory = YES;
	_nameLabel.textAlignment = NSTextAlignmentCenter;
	_nameLabel.textColor = UIColor.secondaryLabelColor;
	_nameLabel.lineBreakMode = NSLineBreakByTruncatingTail;
	[self.contentView addSubview:_nameLabel];

	[NSLayoutConstraint activateConstraints:@[
		[_ringView.topAnchor constraintEqualToAnchor:self.contentView.topAnchor constant:4.0],
		[_ringView.centerXAnchor constraintEqualToAnchor:self.contentView.centerXAnchor],
		[_ringView.widthAnchor constraintEqualToConstant:ringSize],
		[_ringView.heightAnchor constraintEqualToConstant:ringSize],

		[_iconView.centerXAnchor constraintEqualToAnchor:_ringView.centerXAnchor],
		[_iconView.centerYAnchor constraintEqualToAnchor:_ringView.centerYAnchor],
		[_iconView.widthAnchor constraintEqualToConstant:kWAIPGridIconSize],
		[_iconView.heightAnchor constraintEqualToConstant:kWAIPGridIconSize],

		[_checkView.centerXAnchor constraintEqualToAnchor:_ringView.trailingAnchor constant:-4.0],
		[_checkView.centerYAnchor constraintEqualToAnchor:_ringView.topAnchor constant:4.0],
		[_checkView.widthAnchor constraintEqualToConstant:22.0],
		[_checkView.heightAnchor constraintEqualToConstant:22.0],

		[_nameLabel.topAnchor constraintEqualToAnchor:_ringView.bottomAnchor constant:6.0],
		[_nameLabel.leadingAnchor constraintEqualToAnchor:self.contentView.leadingAnchor constant:2.0],
		[_nameLabel.trailingAnchor constraintEqualToAnchor:self.contentView.trailingAnchor constant:-2.0],
	]];

	self.isAccessibilityElement = YES;

	return self;
}

- (void)configureWithIcon:(WAIPIcon *)icon current:(BOOL)current animated:(BOOL)animated {
	UIImage *preview = icon.previewImage;
	self.iconView.image = preview ?: WAIPPlaceholderImage();
	self.iconView.contentMode = preview ? UIViewContentModeScaleAspectFill : UIViewContentModeCenter;
	self.nameLabel.text = icon.displayName;
	self.accessibilityLabel = icon.displayName;
	self.accessibilityTraits = UIAccessibilityTraitButton | (current ? UIAccessibilityTraitSelected : 0);

	BOOL changed = self.isCurrent != current;
	self.isCurrent = current;

	void (^apply)(void) = ^{
		self.ringView.layer.borderColor = current ? WAIPAccentColor().CGColor : UIColor.clearColor.CGColor;
		self.checkView.alpha = current ? 1.0 : 0.0;
		self.checkView.transform = current ? CGAffineTransformIdentity : CGAffineTransformMakeScale(0.4, 0.4);
		self.nameLabel.textColor = current ? UIColor.labelColor : UIColor.secondaryLabelColor;
		self.nameLabel.font = current
			? [UIFont fontWithDescriptor:[[UIFontDescriptor preferredFontDescriptorWithTextStyle:UIFontTextStyleFootnote] fontDescriptorWithSymbolicTraits:UIFontDescriptorTraitBold] size:0]
			: [UIFont preferredFontForTextStyle:UIFontTextStyleFootnote];
	};

	if (animated && changed) {
		[UIView animateWithDuration:0.45 delay:0 usingSpringWithDamping:0.6 initialSpringVelocity:0.6 options:UIViewAnimationOptionAllowUserInteraction animations:apply completion:nil];
	} else {
		apply();
	}
}

- (void)traitCollectionDidChange:(UITraitCollection *)previousTraitCollection {
	[super traitCollectionDidChange:previousTraitCollection];
	// CGColor borders don't follow dark/light mode automatically.
	self.ringView.layer.borderColor = self.isCurrent ? [WAIPAccentColor() resolvedColorWithTraitCollection:self.traitCollection].CGColor : UIColor.clearColor.CGColor;
}

- (void)setHighlighted:(BOOL)highlighted {
	[super setHighlighted:highlighted];
	[UIView animateWithDuration:highlighted ? 0.12 : 0.35 delay:0 usingSpringWithDamping:0.7 initialSpringVelocity:0.5 options:UIViewAnimationOptionAllowUserInteraction | UIViewAnimationOptionBeginFromCurrentState animations:^{
		CGFloat scale = highlighted ? 0.9 : 1.0;
		self.ringView.transform = CGAffineTransformMakeScale(scale, scale);
		self.ringView.alpha = highlighted ? 0.85 : 1.0;
	} completion:nil];
}

- (void)prepareForReuse {
	[super prepareForReuse];
	self.ringView.transform = CGAffineTransformIdentity;
	self.ringView.alpha = 1.0;
}

@end

#pragma mark - Picker view controller

@interface WAIconPickerViewController ()
@property (nonatomic, strong) UICollectionView *collectionView;
@property (nonatomic, copy) NSArray<WAIPIcon *> *icons;
@property (nonatomic, copy, nullable) NSString *currentAlternateName;
@property (nonatomic, assign) BOOL isApplying;
@property (nonatomic, strong) UISelectionFeedbackGenerator *selectionFeedback;
@property (nonatomic, strong) UINotificationFeedbackGenerator *notificationFeedback;
@end

@implementation WAIconPickerViewController

static NSString * const kHeroCellID = @"WAIPHeroCell";
static NSString * const kIconCellID = @"WAIPIconCell";
static NSString * const kHeaderID = @"WAIPHeader";

- (instancetype)init {
	self = [super initWithNibName:nil bundle:nil];
	if (self) {
		self.title = WAIPL(@"App Icon", @"أيقونة التطبيق");
		_icons = WAIPLoadIcons();
		_currentAlternateName = WAIPResolvedCurrentAlternateName();
		_selectionFeedback = [UISelectionFeedbackGenerator new];
		_notificationFeedback = [UINotificationFeedbackGenerator new];
	}
	return self;
}

- (void)viewDidLoad {
	[super viewDidLoad];

	self.view.backgroundColor = UIColor.systemGroupedBackgroundColor;
	self.navigationItem.largeTitleDisplayMode = UINavigationItemLargeTitleDisplayModeNever;

	self.collectionView = [[UICollectionView alloc] initWithFrame:self.view.bounds collectionViewLayout:[self createLayout]];
	self.collectionView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
	self.collectionView.backgroundColor = UIColor.clearColor;
	self.collectionView.alwaysBounceVertical = YES;
	self.collectionView.dataSource = self;
	self.collectionView.delegate = self;

	[self.collectionView registerClass:WAIPHeroCell.class forCellWithReuseIdentifier:kHeroCellID];
	[self.collectionView registerClass:WAIPIconCell.class forCellWithReuseIdentifier:kIconCellID];
	[self.collectionView registerClass:UICollectionViewListCell.class forSupplementaryViewOfKind:UICollectionElementKindSectionHeader withReuseIdentifier:kHeaderID];

	[self.view addSubview:self.collectionView];
}

- (void)viewWillAppear:(BOOL)animated {
	[super viewWillAppear:animated];
	[self.selectionFeedback prepare];
}

#pragma mark Layout

- (UICollectionViewLayout *)createLayout {
	__weak typeof(self) weakSelf = self;

	return [[UICollectionViewCompositionalLayout alloc] initWithSectionProvider:^NSCollectionLayoutSection *(NSInteger sectionIndex, id<NSCollectionLayoutEnvironment> environment) {
		switch (sectionIndex) {
			case WAIPSectionHero:
				return [weakSelf heroSectionLayout];
			default:
				return [weakSelf gridSectionLayoutForEnvironment:environment];
		}
	}];
}

- (NSCollectionLayoutSection *)heroSectionLayout {
	NSCollectionLayoutSize *size = [NSCollectionLayoutSize sizeWithWidthDimension:[NSCollectionLayoutDimension fractionalWidthDimension:1.0]
																  heightDimension:[NSCollectionLayoutDimension estimatedDimension:116.0]];
	NSCollectionLayoutItem *item = [NSCollectionLayoutItem itemWithLayoutSize:size];
	NSCollectionLayoutGroup *group = [NSCollectionLayoutGroup horizontalGroupWithLayoutSize:size subitems:@[item]];
	NSCollectionLayoutSection *section = [NSCollectionLayoutSection sectionWithGroup:group];
	section.contentInsets = NSDirectionalEdgeInsetsMake(12.0, 16.0, 8.0, 16.0);
	return section;
}

- (NSCollectionLayoutSection *)gridSectionLayoutForEnvironment:(id<NSCollectionLayoutEnvironment>)environment {
	CGFloat available = environment.container.effectiveContentSize.width - 32.0;
	NSInteger columns = MAX(3, (NSInteger)floor(available / 96.0));
	CGFloat itemHeight = 72.0 + 8.0 + 28.0;

	NSCollectionLayoutSize *itemSize = [NSCollectionLayoutSize sizeWithWidthDimension:[NSCollectionLayoutDimension fractionalWidthDimension:1.0 / columns]
																	  heightDimension:[NSCollectionLayoutDimension absoluteDimension:itemHeight]];
	NSCollectionLayoutItem *item = [NSCollectionLayoutItem itemWithLayoutSize:itemSize];

	NSCollectionLayoutSize *groupSize = [NSCollectionLayoutSize sizeWithWidthDimension:[NSCollectionLayoutDimension fractionalWidthDimension:1.0]
																	   heightDimension:[NSCollectionLayoutDimension absoluteDimension:itemHeight]];
	NSMutableArray *subitems = [NSMutableArray array];
	for (NSInteger i = 0; i < columns; i++) [subitems addObject:item];
	NSCollectionLayoutGroup *group = [NSCollectionLayoutGroup horizontalGroupWithLayoutSize:groupSize subitems:subitems];

	NSCollectionLayoutSection *section = [NSCollectionLayoutSection sectionWithGroup:group];
	section.interGroupSpacing = 14.0;
	section.contentInsets = NSDirectionalEdgeInsetsMake(6.0, 16.0, 28.0, 16.0);

	NSCollectionLayoutSize *headerSize = [NSCollectionLayoutSize sizeWithWidthDimension:[NSCollectionLayoutDimension fractionalWidthDimension:1.0]
																		heightDimension:[NSCollectionLayoutDimension estimatedDimension:44.0]];
	NSCollectionLayoutBoundarySupplementaryItem *header = [NSCollectionLayoutBoundarySupplementaryItem boundarySupplementaryItemWithLayoutSize:headerSize
																																   elementKind:UICollectionElementKindSectionHeader
																																	 alignment:NSRectAlignmentTop];
	section.boundarySupplementaryItems = @[header];
	return section;
}

#pragma mark Data source

- (NSInteger)numberOfSectionsInCollectionView:(UICollectionView *)collectionView {
	return WAIPSectionCount;
}

- (NSInteger)collectionView:(UICollectionView *)collectionView numberOfItemsInSection:(NSInteger)section {
	switch (section) {
		case WAIPSectionHero: return 1;
		default: return self.icons.count;
	}
}

- (WAIPIcon *)currentIcon {
	for (WAIPIcon *icon in self.icons) {
		if ((icon.alternateName == nil && self.currentAlternateName == nil) || [icon.alternateName isEqualToString:self.currentAlternateName]) {
			return icon;
		}
	}
	return self.icons.firstObject;
}

- (BOOL)isCurrent:(WAIPIcon *)icon {
	if (icon.alternateName == nil) return self.currentAlternateName == nil;
	return [icon.alternateName isEqualToString:self.currentAlternateName];
}

- (UICollectionViewCell *)collectionView:(UICollectionView *)collectionView cellForItemAtIndexPath:(NSIndexPath *)indexPath {
	if (indexPath.section == WAIPSectionHero) {
		WAIPHeroCell *cell = [collectionView dequeueReusableCellWithReuseIdentifier:kHeroCellID forIndexPath:indexPath];
		[cell configureWithIcon:[self currentIcon] totalCount:self.icons.count animated:NO];
		return cell;
	}

	WAIPIconCell *cell = [collectionView dequeueReusableCellWithReuseIdentifier:kIconCellID forIndexPath:indexPath];
	WAIPIcon *icon = self.icons[indexPath.item];
	[cell configureWithIcon:icon current:[self isCurrent:icon] animated:NO];
	return cell;
}

- (UICollectionReusableView *)collectionView:(UICollectionView *)collectionView viewForSupplementaryElementOfKind:(NSString *)kind atIndexPath:(NSIndexPath *)indexPath {
	UICollectionViewListCell *view = [collectionView dequeueReusableSupplementaryViewOfKind:kind withReuseIdentifier:kHeaderID forIndexPath:indexPath];

	UIListContentConfiguration *content;
	if (@available(iOS 15.0, *)) {
		content = [UIListContentConfiguration prominentInsetGroupedHeaderConfiguration];
	} else {
		content = [UIListContentConfiguration groupedHeaderConfiguration];
	}
	content.text = WAIPL(@"Choose an Icon", @"اختر أيقونة");
	content.directionalLayoutMargins = NSDirectionalEdgeInsetsMake(10.0, 4.0, 6.0, 4.0);

	view.contentConfiguration = content;
	view.backgroundConfiguration = [UIBackgroundConfiguration clearConfiguration];
	return view;
}

#pragma mark Delegate

- (BOOL)collectionView:(UICollectionView *)collectionView shouldHighlightItemAtIndexPath:(NSIndexPath *)indexPath {
	return indexPath.section == WAIPSectionIcons;
}

- (BOOL)collectionView:(UICollectionView *)collectionView shouldSelectItemAtIndexPath:(NSIndexPath *)indexPath {
	return indexPath.section == WAIPSectionIcons;
}

- (void)collectionView:(UICollectionView *)collectionView didSelectItemAtIndexPath:(NSIndexPath *)indexPath {
	[collectionView deselectItemAtIndexPath:indexPath animated:NO];
	if (indexPath.section != WAIPSectionIcons) return;

	WAIPIcon *icon = self.icons[indexPath.item];
	[self applyIcon:icon];
}

- (void)applyIcon:(WAIPIcon *)icon {
	if (self.isApplying || [self isCurrent:icon]) return;

	UIApplication *app = UIApplication.sharedApplication;
	if (!app.supportsAlternateIcons) {
		[self.notificationFeedback notificationOccurred:UINotificationFeedbackTypeError];
		[self showAlertWithTitle:WAIPL(@"Not Supported", @"غير مدعوم")
						 message:WAIPL(@"This build of WhatsApp does not support alternate icons.", @"هذه النسخة من واتساب لا تدعم الأيقونات البديلة.")];
		return;
	}

	[self.selectionFeedback selectionChanged];
	self.isApplying = YES;

	NSString *previous = self.currentAlternateName;
	// Optimistic update for an instant, fluid feel.
	self.currentAlternateName = icon.alternateName;
	WAIPSaveAlternateName(icon.alternateName);
	[self refreshSelectionAnimated:YES];

	__weak typeof(self) weakSelf = self;
	gWAIPIsOwnChange = YES;
	[app setAlternateIconName:icon.alternateName completionHandler:^(NSError *error) {
		dispatch_async(dispatch_get_main_queue(), ^{
			__strong typeof(weakSelf) self = weakSelf;
			if (!self) return;
			self.isApplying = NO;

			if (error) {
				self.currentAlternateName = previous;
				WAIPSaveAlternateName(previous);
				[self refreshSelectionAnimated:YES];
				[self.notificationFeedback notificationOccurred:UINotificationFeedbackTypeError];
				[self showAlertWithTitle:WAIPL(@"Couldn't Change Icon", @"تعذّر تغيير الأيقونة")
								 message:error.localizedDescription ?: WAIPL(@"Please try again.", @"حاول مرة أخرى.")];
				return;
			}

			[self.notificationFeedback notificationOccurred:UINotificationFeedbackTypeSuccess];
		});
	}];
	gWAIPIsOwnChange = NO;
}

- (void)refreshSelectionAnimated:(BOOL)animated {
	WAIPHeroCell *hero = (WAIPHeroCell *)[self.collectionView cellForItemAtIndexPath:[NSIndexPath indexPathForItem:0 inSection:WAIPSectionHero]];
	if ([hero isKindOfClass:WAIPHeroCell.class]) {
		[hero configureWithIcon:[self currentIcon] totalCount:self.icons.count animated:animated];
	}

	for (NSIndexPath *indexPath in self.collectionView.indexPathsForVisibleItems) {
		if (indexPath.section != WAIPSectionIcons) continue;
		WAIPIconCell *cell = (WAIPIconCell *)[self.collectionView cellForItemAtIndexPath:indexPath];
		if (![cell isKindOfClass:WAIPIconCell.class]) continue;
		WAIPIcon *icon = self.icons[indexPath.item];
		[cell configureWithIcon:icon current:[self isCurrent:icon] animated:animated];
	}
}

#pragma mark Helpers

- (void)showAlertWithTitle:(NSString *)title message:(NSString *)message {
	UIAlertController *alert = [UIAlertController alertControllerWithTitle:title message:message preferredStyle:UIAlertControllerStyleAlert];
	[alert addAction:[UIAlertAction actionWithTitle:WAIPL(@"OK", @"حسناً") style:UIAlertActionStyleDefault handler:nil]];
	[self presentViewController:alert animated:YES completion:nil];
}

- (void)dismissIconPicker {
	[self dismissViewControllerAnimated:YES completion:nil];
}

@end

#pragma mark - Settings button

static BOOL HitoriNavigationItemHasIconButton(UINavigationItem *navigationItem) {
	for (UIBarButtonItem *item in navigationItem.rightBarButtonItems) {
		if ([item.accessibilityIdentifier isEqualToString:kWAIPButtonIdentifier]) return YES;
	}
	return [navigationItem.rightBarButtonItem.accessibilityIdentifier isEqualToString:kWAIPButtonIdentifier];
}

static void WAAddIconButtonToSettings(WASettingsViewController *self) {
	if (!self || !self.navigationItem) return;
	if (HitoriNavigationItemHasIconButton(self.navigationItem)) return;

	UIImageSymbolConfiguration *config = [UIImageSymbolConfiguration configurationWithWeight:UIImageSymbolWeightMedium];
	UIImage *image = [UIImage systemImageNamed:@"app.badge" withConfiguration:config];

	UIBarButtonItem *iconButton = [[UIBarButtonItem alloc] initWithImage:image
																   style:UIBarButtonItemStylePlain
																  target:self
																  action:@selector(openWAIconPicker)];
	iconButton.accessibilityIdentifier = kWAIPButtonIdentifier;
	iconButton.accessibilityLabel = WAIPL(@"App Icon", @"أيقونة التطبيق");

	NSMutableArray<UIBarButtonItem *> *items = [NSMutableArray arrayWithArray:self.navigationItem.rightBarButtonItems ?: @[]];
	if (items.count == 0 && self.navigationItem.rightBarButtonItem) {
		[items addObject:self.navigationItem.rightBarButtonItem];
	}
	[items addObject:iconButton];

	self.navigationItem.rightBarButtonItems = items;
}

#pragma mark - Hooks

%hook UIApplication

- (void)setAlternateIconName:(NSString *)alternateIconName completionHandler:(void (^)(NSError *error))completionHandler {
	if (gWAIPIsOwnChange || !WAIPHasSavedChoice()) {
		%orig(alternateIconName, completionHandler);
		return;
	}

	NSString *saved = WAIPSavedAlternateName();
	BOOL sameAsSaved = (saved == nil && alternateIconName.length == 0) || [saved isEqualToString:alternateIconName];
	BOOL duringLaunch = (CFAbsoluteTimeGetCurrent() - gWAIPLaunchTime) < kWAIPLaunchGuardSeconds;

	if (!sameAsSaved && duringLaunch) {
		// WhatsApp restoring its own stored icon at launch — keep the user's choice.
		if (completionHandler) {
			dispatch_async(dispatch_get_main_queue(), ^{ completionHandler(nil); });
		}
		return;
	}

	// A later change from WhatsApp's own icon setting: respect it and remember it.
	WAIPSaveAlternateName(alternateIconName);
	%orig(alternateIconName, completionHandler);
}

%end

%hook WASettingsViewController

- (void)viewWillAppear:(BOOL)animated {
	%orig(animated);
	WAAddIconButtonToSettings(self);
}

- (void)viewDidAppear:(BOOL)animated {
	%orig(animated);
	// WhatsApp sometimes rebuilds its bar items after appearing.
	WAAddIconButtonToSettings(self);
}

%new
- (void)openWAIconPicker {
	WAIconPickerViewController *picker = [[WAIconPickerViewController alloc] init];
	UINavigationController *navigationController = [[UINavigationController alloc] initWithRootViewController:picker];
	navigationController.navigationBar.tintColor = WAIPAccentColor();

	picker.navigationItem.leftBarButtonItem = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemClose
																						   target:picker
																						   action:@selector(dismissIconPicker)];

	if (@available(iOS 15.0, *)) {
		navigationController.modalPresentationStyle = UIModalPresentationPageSheet;
		UISheetPresentationController *sheet = navigationController.sheetPresentationController;
		sheet.detents = @[UISheetPresentationControllerDetent.mediumDetent, UISheetPresentationControllerDetent.largeDetent];
		sheet.prefersGrabberVisible = YES;
		sheet.prefersScrollingExpandsWhenScrolledToEdge = YES;
		sheet.prefersEdgeAttachedInCompactHeight = YES;
		sheet.widthFollowsPreferredContentSizeWhenEdgeAttached = YES;
	}

	[self presentViewController:navigationController animated:YES completion:nil];
}

%end

%ctor {
	@autoreleasepool {
		gWAIPLaunchTime = CFAbsoluteTimeGetCurrent();
		%init;
	}
}
