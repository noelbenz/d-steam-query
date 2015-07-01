
This is mostly a simple tool I wrote up when I was debugging my servers. I may or may not expand on it in the future, but here's the code for anyone who's interested.

Currently it seems to be functional. Depending on the query sent, especially if the results are very large, it will time out. On smaller queries it usually completes. It's possible something's wrong in the code but after spending a good while debugging I think Steam's API has a flaw. See the output.txt for a sample results. It looped over the entire list twice and then timed out.
