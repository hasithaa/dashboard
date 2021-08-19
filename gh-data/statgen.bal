import ballerina/time;

const MERGE = "Merge";
const REVIEW = "Review";
const COMPLEXITY = "Complexity";
const TIME = "Time";
const LABELS = "Labels";
const DRAFT = "Draft";
const READY = "Ready";

const REVIEW_UNKNOWN = "REVIEW_UNKNOWN";
const QUICK = "QUICK";
const EASY = "EASY";
const BIG = "BIG";

const RECENT = "RECENT";
const OLD = "OLD";
const STALE = "STALE";

const NO_LBL = "NO_LBL";

type PRKind record {|
    readonly string name;
    string kind;
    string label;
    string cls;
    int count = 0;
|};

type PRStats record {
    map<string> dataClasses = {};
    map<string> dataLabels = {};
    decimal days = 0;
};

final table<PRKind> key(name) prdata = table [
        {name: READY, kind: DRAFT, label: "Ready", cls: "fil-draft"},
        {name: DRAFT, kind: DRAFT, label: "Draft", cls: "fil-ready"},

        {name: "CONFLICTING", kind: MERGE, label: "Conflicting", cls: "fil-conflict"},
        {name: "MERGEABLE", kind: MERGE, label: "In Sync", cls: "fil-sync"},
        {name: "UNKNOWN", kind: MERGE, label: "Checks running", cls: "fil-checking"},

        {name: "CHANGES_REQUESTED", kind: REVIEW, label: "Change Requested", cls: "fil-chg-req"},
        {name: "REVIEW_REQUIRED", kind: REVIEW, label: "Review Required", cls: "fil-rvw-req"},
        {name: "APPROVED", kind: REVIEW, label: "Approved", cls: "fil-rvw-approved"},
        {name: REVIEW_UNKNOWN, kind: REVIEW, label: "Review Unknown", cls: "fil-rvw-unknown"},

        {name: QUICK, kind: COMPLEXITY, label: "Quick Fix", cls: "fil-qfix"},
        {name: EASY, kind: COMPLEXITY, label: "Easy Fix", cls: "fil-efix"},
        {name: BIG, kind: COMPLEXITY, label: "Big Fix", cls: "fil-bfix"},

        {name: RECENT, kind: TIME, label: "Recent", cls: "fil-time-recent"},
        {name: OLD, kind: TIME, label: "Old", cls: "fil-time-old"},
        {name: STALE, kind: TIME, label: "Stale", cls: "fil-time-stale"},

        {name: NO_LBL, kind: LABELS, label: "<No Team Label>", cls: "fil-lbl-no"}

    ];

function updateStat(string kind, string name, PRStats stats) {
    PRKind data;
    if prdata.hasKey(name) {
        data = prdata.get(name);
        data.count = data.count + 1;
    } else {
        data = {name: name, kind: kind, label: name, cls: "fil-" + name, count: 1};
    }
    stats.dataClasses[kind] = data.cls;
    stats.dataLabels[kind] = data.label;
    prdata.put(data);
}

function calculateStats(PullRequest[] prs) returns json|error {

    json[] prsWithFilters = [];
    foreach PullRequest pr in prs {

        // I will use following in generated html. 
        PRStats stats = {};

        if pr.isDraft {
            updateStat(DRAFT, DRAFT, stats);
        } else {
            updateStat(DRAFT, READY, stats);
        }

        // Filter based on merge status
        string mergable = pr.mergeable;
        updateStat(MERGE, mergable, stats);

        // Filter based on review status
        string? reviewDecision = pr.reviewDecision;
        // JBalBug ternary
        updateStat(REVIEW, (reviewDecision is string ? reviewDecision : REVIEW_UNKNOWN), stats);

        // Filter complexity on merge status
        int additions = pr.additions;
        if additions < 100 {
            updateStat(COMPLEXITY, QUICK, stats);
        } else if additions < 500 {
            updateStat(COMPLEXITY, EASY, stats);
        } else {
            updateStat(COMPLEXITY, BIG, stats);
        }

        // Now Filter based on updated time of the PR. 
        string updatedTime = pr.updatedAt;
        // We can use ballerina/time module to convert Github timestamp string.  
        time:Utc updateAt = check time:utcFromString(updatedTime);
        // Calculate days since last update.
        final decimal seconds = time:utcDiffSeconds(NOW, updateAt);
        final decimal days = decimal:round(seconds / (60 * 60 * 24));
        stats.days = days;
        if days >= 10d {
            updateStat(TIME, STALE, stats);
        } else if days >= 5d {
            updateStat(TIME, OLD, stats);
        } else {
            updateStat(TIME, RECENT, stats);
        }

        // Now Filter based on Team/Label.
        Label[]|() labels = pr.labels?.nodes;
        if labels is () || labels.length() == 0 {
            updateStat(LABELS, NO_LBL, stats);
        } else {
            // Let's use query syntax to iterate the all labels and filter label start with team
            string[] teams = from Label label in labels
                let string name = label.name
                where name.startsWith("Team/")
                select name.substring(5);
            foreach var team in teams {
                // We will keep only last team label in each PR. 
                // This is not an issue because we don't use it to render it. 
                updateStat(LABELS, team, stats);
            }
        }

        // Add calcuated fields
        // For this I will create a new Json value and merge it with the original json.
        json jsonFilters = {_cls: stats.dataClasses, _lbl: stats.dataLabels, days: stats.days};
        json prWithFilters = check jsonFilters.mergeJson(pr.toJson()); // JBalBug
        prsWithFilters.push(prWithFilters);
    }

    json filteredData = {filters: prdata.toJson(), prs: prsWithFilters};
    return filteredData;

}
