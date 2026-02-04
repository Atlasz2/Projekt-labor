import create from 'zustand';
import { persist } from 'zustand/middleware';

export const useAppStore = create(
  persist(
    (set) => ({
      user: null,
      setUser: (user) => set({ user }),
      trails: [],
      setTrails: (trails) => set({ trails }),
      currentTrail: null,
      setCurrentTrail: (trail) => set({ currentTrail: trail }),
      userLocation: null,
      setUserLocation: (location) => set({ userLocation: location }),
      completedStations: [],
      addCompletedStation: (stationId) =>
        set((state) => ({
          completedStations: [...state.completedStations, stationId]
        })),
      notifications: true,
      setNotifications: (enabled) => set({ notifications: enabled })
    }),
    {
      name: 'app-storage'
    }
  )
);
