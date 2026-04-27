#import <UIKit/UIKit.h>
#import <Foundation/Foundation.h>

@interface WASettingsViewController : UIViewController
- (void)openWAIconPicker;
@end

@interface WAIconPickerViewController : UITableViewController
@end

static NSString * const kHitoriLiquidGlassEnabledKey = @"com.hitori.LiquidGlassEnabled";

static BOOL HitoriLiquidGlassEnabled(void) {
	return [NSUserDefaults.standardUserDefaults boolForKey:kHitoriLiquidGlassEnabledKey];
}

static void HitoriSetLiquidGlassEnabled(BOOL enabled) {
	[NSUserDefaults.standardUserDefaults setBool:enabled forKey:kHitoriLiquidGlassEnabledKey];
	[NSUserDefaults.standardUserDefaults synchronize];
}

static NSArray<NSString *> *WAIconNames(void) {
	static NSArray<NSString *> *icons;
	static dispatch_once_t onceToken;

	dispatch_once(&onceToken, ^{
		icons = @[
			@"Default",
			@"AppIcon-01", @"AppIcon-02", @"AppIcon-03", @"AppIcon-04", @"AppIcon-05",
			@"AppIcon-06", @"AppIcon-07", @"AppIcon-08", @"AppIcon-09", @"AppIcon-10",
			@"AppIcon-11", @"AppIcon-12", @"AppIcon-13", @"AppIcon-14"
		];
	});

	return icons;
}

static void HitoriWriteLiquidGlassDefaults(void) {
	if (!HitoriLiquidGlassEnabled()) return;

	NSUserDefaults *defaults = NSUserDefaults.standardUserDefaults;

	[defaults setBool:YES forKey:@"liquid_glass_override_enabled"];
	[defaults setBool:YES forKey:@"WALiquidGlassOverrideEnabled"];
	[defaults setBool:YES forKey:@"ios_liquid_glass_enabled"];
	[defaults setBool:YES forKey:@"ios_liquid_glass_launched"];
	[defaults setBool:YES forKey:@"ios_liquid_glass_m1"];
	[defaults setBool:YES forKey:@"ios_liquid_glass_m_1_5"];
	[defaults setBool:YES forKey:@"ios_liquid_glass_m_1_5_context_menu"];
	[defaults setBool:YES forKey:@"ios_liquid_glass_media_m0"];
	[defaults setBool:YES forKey:@"ios_liquid_glass_larger_composer"];
	[defaults setBool:YES forKey:@"ios_liquid_glass_media_editor_enabled"];
	[defaults setBool:YES forKey:@"ios_liquid_glass_calling_improvement_enabled"];
	[defaults setBool:YES forKey:@"ios_liquid_glass_workaround_attachment_tray"];
	[defaults setBool:YES forKey:@"status_viewer_redesign_enabled"];

	[defaults synchronize];
}

static UIImage *WAIconPreviewForName(NSString *iconName) {
	if ([iconName isEqualToString:@"Default"]) {
		return [UIImage imageNamed:@"AppIcon60x60"];
	}

	return [UIImage imageNamed:[NSString stringWithFormat:@"%@@3x", iconName]]
		?: [UIImage imageNamed:[NSString stringWithFormat:@"%@@2x", iconName]]
		?: [UIImage imageNamed:iconName];
}

static UIImage *HitoriRoundedIconPreview(UIImage *image) {
	if (!image) return nil;

	CGSize size = CGSizeMake(46.0, 46.0);
	CGRect rect = CGRectMake(0.0, 0.0, size.width, size.height);

	UIGraphicsImageRendererFormat *format = UIGraphicsImageRendererFormat.defaultFormat;
	format.scale = UIScreen.mainScreen.scale;

	UIGraphicsImageRenderer *renderer = [[UIGraphicsImageRenderer alloc] initWithSize:size format:format];

	return [renderer imageWithActions:^(__unused UIGraphicsImageRendererContext *context) {
		[[UIBezierPath bezierPathWithRoundedRect:rect cornerRadius:14.0] addClip];
		[image drawInRect:rect];
	}];
}

@implementation WAIconPickerViewController

- (instancetype)init {
	self = [super initWithStyle:UITableViewStyleInsetGrouped];

	if (self) {
		self.title = @"App Icon";
	}

	return self;
}

- (void)viewDidLoad {
	[super viewDidLoad];

	self.tableView.rowHeight = 72.0;
	self.tableView.sectionHeaderHeight = 32.0;
	self.tableView.sectionFooterHeight = 18.0;
}

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
	return 2;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
	return section == 0 ? WAIconNames().count : 1;
}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
	return section == 0 ? @"App Icon" : @"Liquid Glass";
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
	if (indexPath.section == 1) {
		UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"HitoriLiquidGlassCell"];

		if (!cell) {
			cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:@"HitoriLiquidGlassCell"];
		}

		BOOL enabled = HitoriLiquidGlassEnabled();

		cell.textLabel.text = @"Enable Liquid Glass";
		cell.detailTextLabel.text = enabled ? @"Enabled, restart WhatsApp to apply" : @"Disabled";
		cell.imageView.image = nil;
		cell.selectionStyle = UITableViewCellSelectionStyleNone;
		cell.accessoryType = UITableViewCellAccessoryNone;

		UISwitch *toggle = [[UISwitch alloc] init];
		toggle.on = enabled;
		[toggle addTarget:self action:@selector(hitoriLiquidGlassSwitchChanged:) forControlEvents:UIControlEventValueChanged];

		cell.accessoryView = toggle;

		return cell;
	}

	UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"HitoriIconCell"];

	if (!cell) {
		cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:@"HitoriIconCell"];
	}

	NSString *iconName = WAIconNames()[indexPath.row];

	cell.textLabel.text = iconName;
	cell.detailTextLabel.text = indexPath.row == 0 ? @"Original WhatsApp icon" : @"Tap to apply";
	cell.imageView.image = HitoriRoundedIconPreview(WAIconPreviewForName(iconName));
	cell.imageView.contentMode = UIViewContentModeScaleAspectFit;
	cell.imageView.clipsToBounds = YES;
	cell.selectionStyle = UITableViewCellSelectionStyleDefault;
	cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
	cell.accessoryView = nil;
	cell.separatorInset = UIEdgeInsetsMake(0.0, 72.0, 0.0, 16.0);

	return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
	[tableView deselectRowAtIndexPath:indexPath animated:YES];

	if (indexPath.section == 1) return;

	if (!UIApplication.sharedApplication.supportsAlternateIcons) {
		[self showAlertWithTitle:@"Not Supported" message:@"This app does not support alternate icons."];
		return;
	}

	NSString *iconName = WAIconNames()[indexPath.row];
	NSString *alternateIconName = [iconName isEqualToString:@"Default"] ? nil : iconName;

	[UIApplication.sharedApplication setAlternateIconName:alternateIconName completionHandler:^(NSError *error) {
		if (!error) return;

		dispatch_async(dispatch_get_main_queue(), ^{
			[self showAlertWithTitle:@"Failed" message:error.localizedDescription ?: @"Could not change icon."];
		});
	}];
}

- (void)hitoriLiquidGlassSwitchChanged:(UISwitch *)sender {
	HitoriSetLiquidGlassEnabled(sender.isOn);
	HitoriWriteLiquidGlassDefaults();

	[self.tableView reloadSections:[NSIndexSet indexSetWithIndex:1] withRowAnimation:UITableViewRowAnimationAutomatic];
	[self showAlertWithTitle:@"Restart Required" message:@"Restart WhatsApp to apply Liquid Glass changes."];
}

- (void)showAlertWithTitle:(NSString *)title message:(NSString *)message {
	UIAlertController *alert = [UIAlertController alertControllerWithTitle:title message:message preferredStyle:UIAlertControllerStyleAlert];

	[alert addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
	[self presentViewController:alert animated:YES completion:nil];
}

- (void)dismissIconPicker {
	[self dismissViewControllerAnimated:YES completion:nil];
}

@end

static BOOL HitoriNavigationItemHasIconButton(UINavigationItem *navigationItem) {
	NSPredicate *predicate = [NSPredicate predicateWithBlock:^BOOL(UIBarButtonItem *item, NSDictionary *bindings) {
		return [item.accessibilityIdentifier isEqualToString:@"WAIconPickerButton"];
	}];

	return [navigationItem.rightBarButtonItems filteredArrayUsingPredicate:predicate].count > 0
		|| [navigationItem.rightBarButtonItem.accessibilityIdentifier isEqualToString:@"WAIconPickerButton"];
}

static void WAAddIconButtonToSettings(WASettingsViewController *self) {
	if (!self || !self.navigationItem) return;
	if (HitoriNavigationItemHasIconButton(self.navigationItem)) return;

	UIBarButtonItem *iconButton =
		[[UIBarButtonItem alloc] initWithImage:[UIImage systemImageNamed:@"app.badge"]
										 style:UIBarButtonItemStylePlain
										target:self
										action:@selector(openWAIconPicker)];

	iconButton.accessibilityIdentifier = @"WAIconPickerButton";

	NSMutableArray<UIBarButtonItem *> *items =
		[NSMutableArray arrayWithArray:self.navigationItem.rightBarButtonItems ?: @[]];

	if (items.count == 0 && self.navigationItem.rightBarButtonItem) {
		[items addObject:self.navigationItem.rightBarButtonItem];
	}

	[items addObject:iconButton];

	self.navigationItem.rightBarButtonItems = items;
}

%hook WASettingsViewController

- (void)viewDidAppear:(BOOL)animated {
	%orig(animated);
	WAAddIconButtonToSettings(self);
}

%new
- (void)openWAIconPicker {
	WAIconPickerViewController *picker = [[WAIconPickerViewController alloc] init];
	UINavigationController *navigationController = [[UINavigationController alloc] initWithRootViewController:picker];

	picker.navigationItem.leftBarButtonItem =
		[[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemClose
													  target:picker
													  action:@selector(dismissIconPicker)];

	[self presentViewController:navigationController animated:YES completion:nil];
}

%end

%group LiquidGlass

%hook WDSLiquidGlass

+ (BOOL)hasLiquidGlassLaunched { return YES; }
+ (BOOL)isM0Enabled { return YES; }
+ (BOOL)isM1Enabled { return YES; }
+ (BOOL)isM1_5Enabled { return YES; }
+ (BOOL)isM1_5ContextMenuEnabled { return YES; }
+ (BOOL)isLargerComposerEnabled { return YES; }
+ (BOOL)isNewLiquidGlassLayoutEnabled { return YES; }

%end

%hook WAABProperties

- (BOOL)ios_liquid_glass_enabled { return YES; }
- (BOOL)ios_liquid_glass_launched { return YES; }
- (BOOL)ios_liquid_glass_m1 { return YES; }
- (BOOL)ios_liquid_glass_m_1_5 { return YES; }
- (BOOL)ios_liquid_glass_m_1_5_context_menu { return YES; }
- (BOOL)ios_liquid_glass_media_m0 { return YES; }
- (BOOL)ios_liquid_glass_larger_composer { return YES; }
- (BOOL)ios_liquid_glass_media_editor_enabled { return YES; }
- (BOOL)ios_liquid_glass_calling_improvement_enabled { return YES; }
- (BOOL)ios_liquid_glass_workaround_attachment_tray { return YES; }
- (BOOL)status_viewer_redesign_enabled { return YES; }

%end

%hook WALiquidGlassOverrideMethodUserDefaults

- (BOOL)isEnabled {
	return YES;
}

%end

%hook IGLiquidGlassExperimentHelper

- (BOOL)isEnabled {
	return YES;
}

%end

%hook _TtC29IGLiquidGlassExperimentHelper39IGLiquidGlassNavigationExperimentHelper

- (BOOL)isEnabled { return YES; }
- (BOOL)isHomeFeedHeaderEnabled { return YES; }

- (void)overrideIsEnabled:(BOOL)arg0 {
	%orig(YES);
}

%end

%hook WAGenericMediaBrowserViewController

- (BOOL)isLiquidGlassLayoutInMediaBrowserEnabled {
	return YES;
}

%end

%hook WAGenericMediaBrowserViewControllerV2

- (BOOL)isLiquidGlassLayoutInMediaBrowserEnabled {
	return YES;
}

%end

%hook WAMediaBrowserVideoCell

+ (void)setNewLiquidGlassLayoutEnabled:(BOOL)arg0 {
	%orig(YES);
}

%end

%end

%ctor {
	@autoreleasepool {
		%init;

		if (HitoriLiquidGlassEnabled()) {
			HitoriWriteLiquidGlassDefaults();
			%init(LiquidGlass);
		}
	}
}