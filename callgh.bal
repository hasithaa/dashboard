import ballerina/http;
import ballerina/io;
import ballerina/time;
import ballerina/lang.array;
import ballerina/lang.value;

configurable string GH_TOKEN = "";

final time:Utc NOW = time:utcNow();

public function main() returns error? {
    http:Client ghAPI = check new ("https://api.github.com/");
    map<string> headers = {Authorization: "bearer " + GH_TOKEN};
    json res = check ghAPI->post("graphql", getAllPRsGQLPayload("ballerina-platform", "ballerina-lang"), headers);
    json[] prs = check value:ensureType(res.data.organization.repository.pullRequests.nodes);
    json prsWithFilters = check filterData(prs);
    check generateDashboardData(prsWithFilters);
}

function getAllPRsGQLPayload(string organization, string repository) returns json {
    string gql = string `{
        organization(login: "${organization}") {
            repository(name: "${repository}") {
            pullRequests(states: OPEN, first: 100, orderBy: {field: UPDATED_AT, direction: DESC}) {
                nodes {
                    number
                    url
                    title
                    createdAt
                    updatedAt
                    isDraft
                    mergeable
                    reviewDecision
                    author {
                        login
                        url
                    }
                    labels(first: 10) {
                        nodes {
                        name
                        }
                    }
                    files(first: 0) {
                        totalCount
                    }
                    deletions
                    additions
                    }
                 }
            }
        }
    }`;
    json payload = {query: gql, variable: {}};
    return payload;
}

function filterData(json[] prs) returns json|error {

    map<int> allFilters = {};
    json[] prsWithFilters = [];
    foreach json pr in prs {

        string[] filters = [];

        // Filter based on merge status
        string mergable = check pr.mergeable;
        filters.push("MERGE_" + mergable);

        // Filter based on review status
        string? reviewDecision = check pr.reviewDecision;
        string reviewFilter = reviewDecision is string ? reviewDecision : "UNKNOWN";
        filters.push("DECISION_" + reviewFilter);

        // Now Filter based on Team/Label.
        // Here I am being lazy, I will try to access the name filed without any data binding. 
        json[]|() labels = check value:ensureType(pr.labels.nodes);
        if labels is () {
            filters.push("Label_NONE");
        } else {
            // Let's use query syntax to iterate the response
            string[] teams = from json label in labels
                let string name = check label.name
                where name.startsWith("Team/")
                select "TEAM_" + name.substring(5);
            filters.push(...teams);
        }

        // Now Filter based on updated time of the PR. 

        // For this we will use `updatedAt` string json field. 
        // `check` expression is useful in this context. 
        string updatedAt = check pr.updatedAt;
        decimal days = check getDaysSinceLastUpdate(updatedAt);
        string timeFilter = check getUpdatedTimeFilters(days);
        filters.push(timeFilter);

        // I will use filters values as class in the website. 
        string classes = filters.reduce(function(string accu, string val) returns string => (accu + " " + val), "");

        // Add calcuated fields
        // For this I will create a new Json value and merge it with the original json.

        json jsonFilters = {classes, days};
        json prWithFilters = check pr.mergeJson(jsonFilters);
        prsWithFilters.push(prWithFilters);

        // Update all filters
        foreach string name in filters {
            // Increment filter count
            allFilters[name] = (allFilters[name] ?: 0) + 1;
        }
    }

    json filteredData = {filters: sortMap(allFilters), prs};
    return filteredData;

}

function getDaysSinceLastUpdate(string updatedTime) returns decimal|error {
    // We can use ballerina/time module to convert Github timestamp string.  
    time:Utc updateAt = check time:utcFromString(updatedTime);

    // Calculate days since last update.
    decimal seconds = time:utcDiffSeconds(NOW, updateAt);
    decimal days = decimal:round(seconds / (60 * 60 * 24));
    return days;
}

function getUpdatedTimeFilters(decimal days) returns string|error {

    if days >= 10d {
        return "Time_STALE";
    } else if days >= 5d {
        return "Time_OLD";
    } else {
        return "Time_NEW";
    }
}

function sortMap(map<int> src) returns map<int> {

    [string, int][] entries = src.entries().toArray().sort(array:ASCENDING, (v) => v[0]);
    map<int> sortedMap = {};
    foreach [string, int] [name, count] in entries {
        sortedMap[name] = count;
    }
    return sortedMap;
}

function generateDashboardData(json data) returns error? {

    check io:fileWriteJson("data/prdata.json", data);
}
