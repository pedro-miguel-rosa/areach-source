import { migrate } from "drizzle-orm/expo-sqlite/migrator";
import { useEffect, useRef, useState } from "react";
import { db } from "@/lib/db/client";
import { migrations } from "@/lib/db/migrations";

type DatabaseMigrationState = {
	error?: Error;
	isPending: boolean;
};

export function useDatabaseMigrations(): DatabaseMigrationState {
	const [isPending, setIsPending] = useState(true);
	const [error, setError] = useState<Error>();
	const didStartRef = useRef(false);

	useEffect(() => {
		if (didStartRef.current) {
			return;
		}

		didStartRef.current = true;

		migrate(db, migrations)
			.then(() => {
				setIsPending(false);
			})
			.catch((migrationError) => {
				if (migrationError instanceof Error) {
					setError(migrationError);
					setIsPending(false);
					return;
				}

				setError(new Error("Failed to run database migrations"));
				setIsPending(false);
			});
	}, []);

	return { isPending, error };
}
