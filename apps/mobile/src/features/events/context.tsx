import { createContext, type Dispatch, type ReactNode, type SetStateAction, useCallback, useContext, useState } from "react";
import type { Event } from "./types";

// Live event context
export type LiveEvent = Event & {
	remoteId: string;
};

type LiveEventContextValue = {
	event: LiveEvent;
};

const LiveEventContext = createContext<LiveEventContextValue | null>(null);

export function LiveEventProvider({ children, value }: { children: ReactNode; value: LiveEventContextValue }) {
	return <LiveEventContext.Provider value={value}>{children}</LiveEventContext.Provider>;
}

export function useLiveEvent() {
	const context = useContext(LiveEventContext);

	if (!context) {
		throw new Error("useLiveEvent must be used within LiveEventProvider");
	}

	return context;
}

// Create event draft context
type CreateEventContextValue = {
	capacity: string;
	createdEventId: string;
	description: string;
	endTime: Date;
	eventDate: Date;
	reset: () => void;
	setCapacity: Dispatch<SetStateAction<string>>;
	setCreatedEventId: Dispatch<SetStateAction<string>>;
	setDescription: Dispatch<SetStateAction<string>>;
	setEndTime: Dispatch<SetStateAction<Date>>;
	setEventDate: Dispatch<SetStateAction<Date>>;
	setStartTime: Dispatch<SetStateAction<Date>>;
	setTitle: Dispatch<SetStateAction<string>>;
	setVenue: Dispatch<SetStateAction<string>>;
	startTime: Date;
	title: string;
	venue: string;
};

const CreateEventContext = createContext<CreateEventContextValue | null>(null);

export function CreateEventProvider({ children }: { children: ReactNode }) {
	const [title, setTitle] = useState("");
	const [venue, setVenue] = useState("");
	const [capacity, setCapacity] = useState("");
	const [description, setDescription] = useState("");
	const [eventDate, setEventDate] = useState(() => new Date());
	const [startTime, setStartTime] = useState(() => new Date());
	const [endTime, setEndTime] = useState(() => new Date(Date.now() + 60 * 60 * 1000));
	const [createdEventId, setCreatedEventId] = useState("");

	const reset = useCallback(() => {
		const nextStartTime = new Date();

		setTitle("");
		setVenue("");
		setCapacity("");
		setDescription("");
		setEventDate(new Date());
		setStartTime(nextStartTime);
		setEndTime(new Date(nextStartTime.getTime() + 60 * 60 * 1000));
		setCreatedEventId("");
	}, []);

	return (
		<CreateEventContext.Provider
			value={{
				capacity,
				createdEventId,
				description,
				endTime,
				eventDate,
				reset,
				setCapacity,
				setCreatedEventId,
				setDescription,
				setEndTime,
				setEventDate,
				setStartTime,
				setTitle,
				setVenue,
				startTime,
				title,
				venue,
			}}
		>
			{children}
		</CreateEventContext.Provider>
	);
}

export function useCreateEventDraft() {
	const context = useContext(CreateEventContext);

	if (!context) {
		throw new Error("useCreateEventDraft must be used within CreateEventProvider");
	}

	return context;
}
