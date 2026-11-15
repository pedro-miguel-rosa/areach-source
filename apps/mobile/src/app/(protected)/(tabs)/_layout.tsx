import { Tabs } from "@/lib/navigation/tabs";

export default function ProtectedTabsLayout() {
	return (
		<Tabs>
			<Tabs.Trigger name="index">
				<Tabs.Trigger.Icon sf={{ default: "house", selected: "house.fill" }} />
				<Tabs.Trigger.Label>Home</Tabs.Trigger.Label>
			</Tabs.Trigger>
			<Tabs.Trigger name="events">
				<Tabs.Trigger.Icon sf={{ default: "calendar", selected: "calendar" }} />
				<Tabs.Trigger.Label>Events</Tabs.Trigger.Label>
			</Tabs.Trigger>
			<Tabs.Trigger name="profile">
				<Tabs.Trigger.Icon sf={{ default: "person.crop.circle", selected: "person.crop.circle.fill" }} />
				<Tabs.Trigger.Label>Profile</Tabs.Trigger.Label>
			</Tabs.Trigger>
		</Tabs>
	);
}
