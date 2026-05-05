# Power BI Setup — Direct Connection to SQLite

Power BI doesn't ship with a native SQLite connector, but it works cleanly through an ODBC driver. This guide walks through a one-time setup that lets you refresh the dashboard straight from `swim_club.db`.

## One-time setup (≈ 10 minutes)

### 1. Install the SQLite ODBC driver

Download **SQLite ODBC Driver** by Christian Werner — it's free and widely used:

https://www.ch-werner.de/sqliteodbc/

On the download page, pick:
- **sqliteodbc_w64.exe** if you're on 64-bit Windows (most laptops)
- **sqliteodbc.exe** if you're on 32-bit Windows

Run the installer with default options.

### 2. Register a DSN (Data Source Name)

A DSN is a named pointer to your database file, which Power BI uses to find it.

1. Press **Start** → search **"ODBC Data Sources (64-bit)"** → open it
2. Go to the **User DSN** tab → click **Add...**
3. Choose **SQLite3 ODBC Driver** → click **Finish**
4. In the configuration dialog:
    - **Data Source Name:** `SwimClub` (this is the name Power BI will show)
    - **Database Name:** click Browse and pick your `swim_club.db` file
    - Leave other options at their defaults
    - Click **OK**

### 3. Connect Power BI

1. Open **Power BI Desktop** → **Home → Get Data → More...**
2. Search for **"ODBC"** → select **ODBC** → click **Connect**
3. In the DSN dropdown, pick **`SwimClub`** → click **OK**
4. If prompted for credentials, choose **Default or Custom** with empty username/password — SQLite has no authentication → click **Connect**
5. The Navigator shows every table and view — tick only the six views (they're the dashboard layer):
    - `v_race_results`
    - `v_swimmer_dim`
    - `v_season_points`
    - `v_weekly_trends`
    - `v_coach_scorecard`
    - `v_nomination_audit`
6. Click **Load**

## Refreshing the dashboard

Whenever the source data changes:

1. Run `python scripts/load_data.py` from the project folder to rebuild `swim_club.db`
2. In Power BI Desktop, click **Home → Refresh**

That's it — the views pick up the new data automatically.

## Recommended data model in Power BI

Use `v_race_results` as the fact table and build relationships to the lookup views:

```
v_race_results (fact)                 ← 772 rows, one per race-lane
├── v_swimmer_dim        on swimmerID            (many-to-one)
├── v_coach_scorecard    on coach_name           (many-to-one)
├── v_season_points      on swimmerID            (many-to-one)
└── v_weekly_trends      (kept separate - used on the Trending page only)
```

Mark `v_race_results` as the fact table in Model view (right-click → Mark as fact table). This lets Power BI optimise query plans.

## Dashboard page plan

| Page              | Key visuals                                              | Uses views |
|-------------------|----------------------------------------------------------|------------|
| Season Overview   | KPI cards, division-winner cards, points-by-division bar | `v_season_points`, `v_coach_scorecard` |
| Swimmer Trending  | Line chart (time vs week), drill-through per swimmer     | `v_weekly_trends` |
| Coach Effectiveness | Ranked bar chart, DNF rate heatmap                     | `v_coach_scorecard` |
| Data Quality      | Donut (nomination status), table of raced-without-nom    | `v_nomination_audit` |

## Publishing

Once the dashboard is built:

- **File → Publish → To Power BI** (requires free Power BI account)
- Grab the "Publish to web" URL and paste it into your repo README so recruiters can view the live dashboard without installing anything
- **Caveat:** publishing to web makes the data publicly visible — this is a portfolio dataset so it's fine, but don't do this with real client data
