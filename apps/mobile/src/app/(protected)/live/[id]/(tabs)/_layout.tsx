import { Tabs } from "@/lib/navigation/tabs";

export default function LiveEventTabsLayout() {
	return (
		<Tabs>
			<Tabs.Trigger name="index">
				<Tabs.Trigger.Icon sf={{ default: "square.grid.2x2", selected: "square.grid.2x2.fill" }} />
				<Tabs.Trigger.Label>Overview</Tabs.Trigger.Label>
			</Tabs.Trigger>
			<Tabs.Trigger name="attendees">
				<Tabs.Trigger.Icon sf={{ default: "person.2", selected: "person.2.fill" }} />
				<Tabs.Trigger.Label>Attendees</Tabs.Trigger.Label>
			</Tabs.Trigger>
			<Tabs.Trigger name="camera">
				<Tabs.Trigger.Icon sf={{ default: "camera", selected: "camera.fill" }} />
				<Tabs.Trigger.Label>Camera</Tabs.Trigger.Label>
			</Tabs.Trigger>
		</Tabs>
	);
}
