#import <UIKit/UIKit.h>

static NSArray<NSString *> *WAIconNames(void) {
	return @[
		@"Default",
		@"AppIcon-01",
		@"AppIcon-02",
		@"AppIcon-03",
		@"AppIcon-04",
		@"AppIcon-05",
		@"AppIcon-06",
		@"AppIcon-07",
		@"AppIcon-08",
		@"AppIcon-09",
		@"AppIcon-10",
		@"AppIcon-11",
		@"AppIcon-12",
		@"AppIcon-13",
		@"AppIcon-14"
	];
}

static UIImage *WAIconPreviewForName(NSString *iconName) {
	if ([iconName isEqualToString:@"Default"]) {
		return [UIImage imageNamed:@"AppIcon60x60"];
	}

	UIImage *image = [UIImage imageNamed:[NSString stringWithFormat:@"%@@3x", iconName]];

	if (image) {
		return image;
	}

	image = [UIImage imageNamed:[NSString stringWithFormat:@"%@@2x", iconName]];

	if (image) {
		return image;
	}

	return [UIImage imageNamed:iconName];
}

@interface WAIconPickerViewController : UITableViewController
@end

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
	self.tableView.sectionHeaderHeight = 10.0;
	self.tableView.sectionFooterHeight = 10.0;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
	return WAIconNames().count;
}

- (CGFloat)tableView:(UITableView *)tableView heightForRowAtIndexPath:(NSIndexPath *)indexPath {
	return 72.0;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
	UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"WAIconCell"];

	if (!cell) {
		cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:@"WAIconCell"];
	}

	NSString *iconName = WAIconNames()[indexPath.row];
	UIImage *previewImage = WAIconPreviewForName(iconName);

	cell.textLabel.text = iconName;
	cell.detailTextLabel.text = indexPath.row == 0 ? @"Original WhatsApp icon" : @"Tap to apply";
	cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
	cell.selectionStyle = UITableViewCellSelectionStyleDefault;
	cell.separatorInset = UIEdgeInsetsMake(0, 74, 0, 16);
	cell.accessoryView = nil;

	if (previewImage) {
		cell.imageView.image = previewImage;
		cell.imageView.contentMode = UIViewContentModeScaleAspectFill;
		cell.imageView.layer.cornerRadius = 9.0;
		cell.imageView.layer.masksToBounds = YES;
		cell.imageView.clipsToBounds = YES;
	} else {
		cell.imageView.image = nil;
	}

	return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
	[tableView deselectRowAtIndexPath:indexPath animated:YES];

	NSString *selectedIcon = WAIconNames()[indexPath.row];
	NSString *iconName = [selectedIcon isEqualToString:@"Default"] ? nil : selectedIcon;

	if (![[UIApplication sharedApplication] supportsAlternateIcons]) {
		[self showAlertWithTitle:@"Not Supported" message:@"This app does not support alternate icons."];
		return;
	}

	[[UIApplication sharedApplication] setAlternateIconName:iconName completionHandler:^(NSError *error) {
		dispatch_async(dispatch_get_main_queue(), ^{
			if (error) {
				[self showAlertWithTitle:@"Failed" message:error.localizedDescription ?: @"Could not change icon."];
			}
		});
	}];
}

- (void)showAlertWithTitle:(NSString *)title message:(NSString *)message {
	UIAlertController *alert = [UIAlertController alertControllerWithTitle:title
																   message:message
															preferredStyle:UIAlertControllerStyleAlert];

	[alert addAction:[UIAlertAction actionWithTitle:@"OK"
											  style:UIAlertActionStyleDefault
											handler:nil]];

	[self presentViewController:alert animated:YES completion:nil];
}

- (void)dismissIconPicker {
	[self dismissViewControllerAnimated:YES completion:nil];
}

@end

@interface WASettingsViewController : UIViewController
@end

static void WAAddIconButtonToSettings(WASettingsViewController *self) {
	if (!self || !self.navigationItem) {
		return;
	}

	UIImage *symbolImage = nil;

	if (@available(iOS 13.0, *)) {
		symbolImage = [UIImage systemImageNamed:@"app.badge"];
	}

	UIBarButtonItem *iconButton = symbolImage
		? [[UIBarButtonItem alloc] initWithImage:symbolImage
										   style:UIBarButtonItemStylePlain
										  target:self
										  action:@selector(openWAIconPicker)]
		: [[UIBarButtonItem alloc] initWithTitle:@"Icon"
										   style:UIBarButtonItemStylePlain
										  target:self
										  action:@selector(openWAIconPicker)];

	iconButton.accessibilityIdentifier = @"WAIconPickerButton";

	NSMutableArray *items = [NSMutableArray array];

	if (self.navigationItem.rightBarButtonItems.count > 0) {
		[items addObjectsFromArray:self.navigationItem.rightBarButtonItems];
	} else if (self.navigationItem.rightBarButtonItem) {
		[items addObject:self.navigationItem.rightBarButtonItem];
	}

	for (UIBarButtonItem *item in items) {
		if ([item.accessibilityIdentifier isEqualToString:@"WAIconPickerButton"]) {
			return;
		}
	}

	[items addObject:iconButton];
	self.navigationItem.rightBarButtonItems = items;
}

%hook WASettingsViewController

- (void)viewDidLoad {
	%orig;

	WAAddIconButtonToSettings(self);
}

- (void)viewWillAppear:(BOOL)animated {
	%orig(animated);

	WAAddIconButtonToSettings(self);
}

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