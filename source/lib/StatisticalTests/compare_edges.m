%
% Copyright (c) 2013, Carnegie Mellon University.
% All rights reserved.
%
% Redistribution and use in source and binary forms, with or without
% modification, are permitted provided that the following conditions
% are met:
% 1. Redistributions of source code must retain the above copyright
%    notice, this list of conditions and the following disclaimer.
% 2. Redistributions in binary form must reproduce the above copyright
%    notice, this list of conditions and the following disclaimer in the
%    documentation and/or other materials provided with the distribution.
% 3. Neither the name of the University nor the names of its contributors
%    may be used to endorse or promote products derived from this software
%    without specific prior written permission.
%
% THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS
% ``AS IS'' AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT
% LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR
% A PARTICULAR PURPOSE ARE DISCLAIMED.  IN NO EVENT SHALL THE COPYRIGHT
% HOLDERS OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT,
% INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING,
% BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS
% OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED
% AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT
% LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY
% WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE
% POSSIBILITY OF SUCH DAMAGE.
%

% $cmuPDL: compare_edges.m,v 1.4 2010/04/06 09:22:03 rajas Exp $
%%
% This matlab script compares the edge latency distributions of the
% edge latencies passed into it and returns whether they are the same.  The
% output file returned is of the format
% <edge row_num> <accept null hypothesis?> <p-value> <avg. latency s0>
% <stddev s0> <avg. latency s1> <stddev s1>
%
% Note that this script will summarily decide to reject the null hypothesis
% if no edge latencies are present for the edge in s0 xor s1.  In this case
% the p-value returned is -1.
%
% If there is not enough data to a given edge edges using the chosen statistical
% test, the null hypothesis will be accepted and a p-value of -1 returned.
%
% If there is no data for the given edge, no information for the edge
% will be computed.
%
% Before comparing edge latency distributions, this script 'smooths' the input
% edge latencies by dividing by 1000 to convert to milliseconds and then
% rounding to the nearest integer
%
% @param s0_edge_latencies: Edge latencies from the zeroth
%        snapshot.  This is in MATLAB sparse file format.  Format is:
%        <row num> <col num> <edge latency>
% @param s1_edge_latencies: Edge latencies from the first
%        shapshot.  This is in MATLAB sparse file format.
% @param output_file.dat: Where the output of this script will be placed
% @param stats_file: Unused by this script
%%
function [] = compare_edges(s0_file, s1_file, output_file, stats_file)    

    s0_data = load(s0_file);

    if(~isempty(s0_data)),
       s0_data = spconvert(s0_data);
    end

    s1_data = load(s1_file);
    if(~isempty(s1_data)),
       s1_data = spconvert(s1_data);
    end
 
    max_rows = max(size(s0_data, 1), size(s1_data, 1));
    
    outfid = fopen(output_file, 'w');
        
    % Iterate through rows of the edge matrix, 
    for i = 1:max_rows,
        
        if( i <= size(s0_data, 1))
            s0_edge_latencies = s0_data(i, :);
            s0_edge_latencies = full(s0_edge_latencies);
            s0_edge_latencies = s0_edge_latencies(find(s0_edge_latencies ~= 0));
        else 
            s0_edge_latencies = [];
        end
        
        if (i <= size(s1_data, 1)),
            s1_edge_latencies = s1_data(i, :); 
            s1_edge_latencies = full(s1_edge_latencies);
            s1_edge_latencies = s1_edge_latencies(find(s1_edge_latencies ~= 0));
        else 
            s1_edge_latencies = [];
        end
        
        if(isempty(s0_edge_latencies) && isempty(s1_edge_latencies)),
          % This might be RPC call/reply for which an RPC call/RPC reply
          % instrumentation point pair was not added in the code
          fprintf(outfid, '%d %d %3.2f %3.2f %3.2f %3.2f %3.2f\n', ...
                  i, 0, 0, 0, 0, 0, 0);

           continue;
        end
        
        
        %%
        % This block of code checks to see if one of the edge latency
        % vectors for s0 or s1 are empty.  If so, it summarily outputs
        % a decision and does not apply the kstest.
        %%
        if(isempty(s0_edge_latencies)),
            % This edge was only seen in the s1 data
            fprintf(outfid, '%d %d %3.2f %3.2f %3.2f %3.2f %3.2f\n', ...
                    i, 0, -1, 0, 0, mean(s1_edge_latencies), std(s1_edge_latencies));
            continue;
        end
        
        if(isempty(s1_edge_latencies)),
            % This edge was only seen in the s0 data
            fprintf(outfid, '%d %d %3.2f %3.2f %3.2f %3.2f %3.2f\n', ...
                    i, 0, -2, mean(s0_edge_latencies), std(s0_edge_latencies), 0, 0);
            continue;
        end


        %% This block of code runs the kstest algorithm.
        s0_size = size(s0_edge_latencies, 2);
        s1_size = size(s1_edge_latencies, 2);

        % Matlab help suggests that kstest2 produces reasonable estimates
        % when the following condition is false.
        e = 0.0001;
        if(s0_size*s1_size/(s0_size + s1_size + e) < 4),
            fprintf(outfid, '%d %d %3.2f %3.2f %3.2f %3.2f %3.2f\n', ...
                i, 0, -3, mean(s0_edge_latencies), std(s0_edge_latencies), ...
                    mean(s1_edge_latencies), std(s1_edge_latencies));
            continue;
        end
          

        s0_edge_latencies_smoothed = round(s0_edge_latencies/1000);
        s1_edge_latencies_smoothed = round(s1_edge_latencies/1000);
        [h, p] = kstest2(s0_edge_latencies_smoothed, s1_edge_latencies_smoothed, .05, 'larger');
        
        fprintf(outfid, '%d %d %f %3.2f %3.2f %3.2f %3.2f\n', ...
                i, h, p, mean(s0_edge_latencies), std(s0_edge_latencies), ...
                    mean(s1_edge_latencies), std(s1_edge_latencies));
    end
    fclose(outfid);
end
