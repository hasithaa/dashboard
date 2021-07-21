curl -H "Authorization: bearer  ${packagePAT}" -X POST -d @pr_fe.json https://api.github.com/graphql > data/PR_FE.json
curl -H "Authorization: bearer  ${packagePAT}" -X POST -d @pr_ct.json https://api.github.com/graphql > data/PR_CT.json
curl -H "Authorization: bearer  ${packagePAT}" -X POST -d @pr_rt.json https://api.github.com/graphql > data/PR_RT.json