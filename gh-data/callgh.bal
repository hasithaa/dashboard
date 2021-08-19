import ballerina/io;
import ballerina/http;
import ballerina/time;
// import ballerina/lang.value;

configurable string GH_TOKEN = "";

final time:Utc NOW = time:utcNow();

public function main() returns error? {
    http:Client ghAPI = check new ("https://api.github.com/");
    map<string> headers = {Authorization: "bearer " + GH_TOKEN};

    json res = check ghAPI->post("graphql", getAllPRsGQLPayload("ballerina-platform", "ballerina-lang"), headers);

    json nodes = check res.data.organization.repository.pullRequests.nodes;
    PullRequest[] prs = check nodes.cloneWithType();
    json prsWithFilters = check calculateStats(prs);

    // JBal Bug. Had to call toJSON to preseved some content.
    check io:fileWriteJson("data/prdata.json", prsWithFilters.toJson());
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

type Author record {|
    string login;
    string url;
|};

type Label record {|
    string name;
|};

type Labels record {|
    Label[]? nodes;
|};

type Files record {|
    int totalCount;
|};

type PullRequest record {|
    int additions;
    int deletions;
    Author author;
    boolean isDraft;
    string title;
    string url;
    Labels? labels;
    int number;
    string createdAt;
    string mergeable;
    string? reviewDecision;
    Files files;
    string updatedAt;
|};