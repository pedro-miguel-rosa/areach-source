import { SymbolView, type SymbolViewProps } from "expo-symbols";

const iconMap = {
	alertTriangle: { ios: "exclamationmark.triangle", android: "warning", web: "warning" },
	appearance: { ios: "circle.lefthalf.filled", android: "contrast", web: "contrast" },
	arrowLeft: { ios: "arrow.left", android: "arrow_back", web: "arrow_back" },
	bell: { ios: "bell", android: "notifications", web: "notifications" },
	calendar: { ios: "calendar", android: "calendar_month", web: "calendar_month" },
	calendarCheck: { ios: "calendar.badge.checkmark", android: "event_available", web: "event_available" },
	camera: { ios: "camera", android: "photo_camera", web: "photo_camera" },
	cameraFilled: { ios: "camera.fill", android: "photo_camera", web: "photo_camera" },
	check: { ios: "checkmark", android: "check", web: "check" },
	checkCircle: { ios: "checkmark.circle", android: "check_circle", web: "check_circle" },
	circleFilled: { ios: "circle.fill", android: "circle", web: "circle" },
	chevronLeft: { ios: "chevron.left", android: "arrow_back", web: "arrow_back" },
	chevronRight: { ios: "chevron.right", android: "chevron_right", web: "chevron_right" },
	clock: { ios: "clock", android: "schedule", web: "schedule" },
	copy: { ios: "doc.on.doc", android: "content_copy", web: "content_copy" },
	delete: { ios: "trash", android: "delete", web: "delete" },
	ellipsis: { ios: "ellipsis", android: "more_horiz", web: "more_horiz" },
	evaluation: { ios: "checklist", android: "fact_check", web: "fact_check" },
	eye: { ios: "eye.fill", android: "visibility", web: "visibility" },
	eyeOff: { ios: "eye.slash.fill", android: "visibility_off", web: "visibility_off" },
	help: { ios: "questionmark.circle", android: "help_outline", web: "help_outline" },
	info: { ios: "info.circle", android: "info", web: "info" },
	language: { ios: "globe", android: "language", web: "language" },
	location: { ios: "mappin", android: "location_on", web: "location_on" },
	logOut: { ios: "rectangle.portrait.and.arrow.right", android: "logout", web: "logout" },
	grid: { ios: "square.grid.2x2", android: "grid_view", web: "grid_view" },
	gridFilled: { ios: "square.grid.2x2.fill", android: "grid_view", web: "grid_view" },
	home: { ios: "house", android: "home", web: "home" },
	homeFilled: { ios: "house.fill", android: "home", web: "home" },
	lock: { ios: "lock", android: "lock", web: "lock" },
	mail: { ios: "envelope", android: "mail", web: "mail" },
	map: { ios: "map", android: "map", web: "map" },
	mapFilled: { ios: "map.fill", android: "map", web: "map" },
	nosign: { ios: "nosign", android: "block", web: "block" },
	notifications: { ios: "bell.badge", android: "notifications_active", web: "notifications_active" },
	plus: { ios: "plus", android: "add", web: "add" },
	plusCircle: { ios: "plus.circle", android: "add_circle_outline", web: "add_circle_outline" },
	plusCircleFilled: { ios: "plus.circle.fill", android: "add_circle", web: "add_circle" },
	share: { ios: "square.and.arrow.up", android: "ios_share", web: "ios_share" },
	ticket: { ios: "ticket", android: "confirmation_number", web: "confirmation_number" },
	user: { ios: "person", android: "person", web: "person" },
	userCircle: { ios: "person.crop.circle", android: "account_circle", web: "account_circle" },
	userCircleFilled: { ios: "person.crop.circle.fill", android: "account_circle", web: "account_circle" },
	users: { ios: "person.2", android: "groups_2", web: "groups_2" },
	usersFilled: { ios: "person.2.fill", android: "groups", web: "groups" },
	xMark: { ios: "xmark", android: "close", web: "close" },
} satisfies Record<string, SymbolViewProps["name"]>;

export type IconName = keyof typeof iconMap;

export type IconProps = {
	color?: SymbolViewProps["tintColor"];
	name: IconName;
	style?: SymbolViewProps["style"];
	size?: number;
};

export function Icon(props: IconProps) {
	const { color, name, size = 18, style } = props;

	return <SymbolView name={iconMap[name]} size={size} style={style} tintColor={color} />;
}
