# FitAnalyzer

A Mac app for looking at `.fit` activity files — the format written by Garmin watches, Zwift and most other fitness devices and apps. Open a file to see its summary, route and charts, then cut the activity into your own laps to compare intervals.

Files are only read, never modified, and nothing leaves your Mac except map tile requests to Apple Maps.

## Requirements

- macOS 15 or later
- Xcode 16 or later to build

There are no third-party dependencies; the FIT decoder is part of the app.

## Building and running

```bash
open FitAnalyzer.xcodeproj
```

Then press Run (⌘R) in Xcode. The app is signed to run locally, so no developer account is needed.

## Opening activities

Any of these work:

- **File › Open…** (⌘O), or the **+** button in the toolbar
- Drag one or more `.fit` files onto the window
- In Finder, right-click a `.fit` file and choose **Open With › FitAnalyzer**

Every opened activity is listed in the sidebar. Click one to view it; right-click it and choose **Remove** to close it. Activities are not kept between launches.

The **Metric / Imperial** switch in the toolbar changes units everywhere. Runs, walks and hikes show pace; other sports show speed.

## Overview tab

- **Summary** — distance, moving and elapsed time, pace or speed, elevation gain and loss, heart rate, power, cadence and calories. Only values the file actually contains are shown.
- **Route map** — shown when the file has GPS data. Treadmill and other indoor activities have no map.
- **Charts** — pace or speed, heart rate, power, cadence and elevation, plotted against time or distance. A chart is left out if the file has no data for it.
- **Laps** — the laps recorded by the device, when there is more than one.

## Intervals tab

The Intervals tab lets you define your own laps, independent of what the device recorded. Laps are held only while the app is open; they are not written back to the file.

### Creating laps

Choose **Create Laps** and pick a distance: every 0.25, 0.5, 1 or 5 miles, or in metric every 0.5, 1, 2, 5 or 10 km. You can also start from **Laps Recorded in File**. Choosing again replaces the current laps.

Switching between metric and imperial clears the laps of every open activity, since they were defined in the other unit.

### The lap table

Each lap shows distance, time, average pace, average speed, max pace, max speed, and average, max and min heart rate. Times exclude pauses.

- **Change a lap's distance** — double-click its distance, type a new value and press Return. Later laps keep their lengths and shift along; the final lap takes up whatever distance is left.
- **Combine laps** — select two or more rows and click **Combine** (⌘J), or right-click the selection. Everything from the first to the last selected lap becomes one lap.
- **Show or hide columns** — click **Columns** and tick the ones you want. The choice is remembered.
- **Start Over** — removes all laps, leaving one lap covering the whole activity.

For example, to analyse a workout of half-mile intervals with quarter-mile recoveries: create laps every 0.25 mi, set the first lap's distance to your warm-up, then combine each pair of quarter-miles that makes up an interval.

### Lap charts

- **Pace (or speed) by lap** — one bar per lap, as wide as the lap's distance, so recoveries and intervals keep their real proportions. Bar height is the average; the line above each bar is the lap's best. Laps faster than the overall average are blue, slower ones teal.
- **Heart rate by lap** — a shaded bar from each lap's minimum to maximum, with a line at the average.

Selecting rows in the table highlights those laps in both charts.

## Project layout

| File | Purpose |
|---|---|
| `FitAnalyzer/FitDecoder.swift` | Decodes the FIT binary format into messages |
| `FitAnalyzer/Activity.swift` | Builds an activity (samples, laps, summary) from decoded messages |
| `FitAnalyzer/Intervals.swift` | Cuts an activity into laps at arbitrary distances |
| `FitAnalyzer/ContentView.swift` | Window, sidebar and file opening |
| `FitAnalyzer/ActivityDetailView.swift` | Overview tab |
| `FitAnalyzer/IntervalsView.swift`, `IntervalCharts.swift` | Intervals tab |
| `FitAnalyzer/Units.swift` | Unit conversion and formatting |

Sample `.fit` files for local testing go in `test-data/`, which is ignored by git because activity files usually contain personal GPS tracks.
