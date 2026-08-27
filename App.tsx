import React from 'react';
import { SQLiteProvider } from 'expo-sqlite';
import { JaleApp } from './src/JaleApp';
import { migrateDatabase } from './src/database';
import { SubscriptionProvider } from './src/subscription';

export default function App() {
  return (
    <SubscriptionProvider>
      <SQLiteProvider databaseName="jale.db" onInit={migrateDatabase}>
        <JaleApp />
      </SQLiteProvider>
    </SubscriptionProvider>
  );
}
