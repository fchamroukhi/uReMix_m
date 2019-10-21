function [klas, params, Posterior, gmm_density, stored_K, stored_J] = robust_em_RE_PRM(x, Y, spline_order, spline_type, nknots)
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

% Robust EM algorithm for Random Effects Polynomial Spline Regression Mixture Model (PSRM)
% M: Spline order
%
%
%
%
% by Faicel Chamroukhi, December 2012
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
warning off all

[n, m] = size(Y);
Y_in  = Y;


%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
% Construction of the desing matrix
% uniform knots locations %
knots = linspace(0,1,nknots+2); % including the first and the two boudaries knots
% knots(end-1) = x(end)+x(end)-x(end-1)+x(end)-x(end-1);
knots(end) = x(end)+x(end)-x(end-1);
% knots = [x(1) knots(2:end-1) x(end)+x(end)-x(end-1)];% interior and the two boudaries knots
M = spline_order;
dimBeta =  M + nknots;

% construct the design matrix for a spline or B-spline of order M
switch spline_type
    case 'spline'
        knots =  knots(2:end-1);    % take the interior knots
        X = splinebasis(x, knots, spline_order);
    case'B-spline'
        X = bsplinebasis(x, knots, spline_order);
    otherwise
        error('not included regression model');
end 

% close all
% figure,
% plot(X,'x-')
% return;
% pause
%n regularly sampled curves
Xstack = repmat(X,n,1);% desing matrix [(n*m) x (dimBeta)]
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%


% threshold for testing the convergence
Epsilon = 1e-6;

%------ Step 1 initialization ----- %
Beta    = 1;
K       = n;
% -----------(28) ---------------- %
gama        = 1e-6;
Y_stack_tmp = repmat(Y',n,[]); % [mxn x n]
Y_stack     = (reshape((Y_stack_tmp(:))',m,[]))'; %[nxn x m];
dij         = sum((Y_stack - repmat(Y,n,[])).^2, 2);
dmin        = min(dij(dij>0));
Q           = dmin;

%%%%
Ytild = reshape(Y',[],1); % []
%%%

%Initialize the mixing proportins
Alphak = 1/K*ones(K,1);
Pik = 1/K*ones(K,1);

% Initialize the regression parameters and the variances
Betak   = zeros(dimBeta,n);
Sigmak2  = zeros(K,1);

for k=1:K
    % ------- step 2  (27)  ------- %
    %betak  = inv(Phi'*Phi + 1e-4*eye(dimBeta))*Phi'*Y_in(k,:)';
    betak  = (X'*X + 1e-6*eye(dimBeta))\(X'*Y_in(k,:)'); % % inversion problem for spline of order 1 (polynomial degree=1)
    Betak(:,k) = betak;
    muk = X*betak;
    %Dk = sum((reshape(X,n,m) - reshape(muk',n,m)).^2, 2);
    Dk = sum((Y_in - ones(n,1)*muk').^2, 2);
    Dk = sort(Dk);
    Sigmak2(k)=  Dk(ceil(sqrt(K)));%sum(Y_in(k,:)' - muk);%Dk(ceil(sqrt(K)));%.001;%%;%
    % --------------------------- %
end

%--------- Step 3 (4) --------%

% compute the pposterior cluster probabilites (responsibilities) for the
% initial guess of the model parameters
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%                           %
%       E-Step              %
%                           %
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
PikFik = zeros(n, K);
log_fk_xij = zeros(n*m,K);
log_Pik_fk_Xi = zeros(n,K);
log_Pik_Fik = zeros(n,K);
% E-Step
for k=1:K
    pik = Pik(k);
    betak = Betak(:,k); sigmak2 = Sigmak2(k);
    %fik = normpdf(X,muk,sigmak); %Gaussian density
    z=((Ytild-Xstack*betak).^2)/sigmak2;
    log_fk_xij(:,k) = - 0.5*(log(2*pi)+log(sigmak2)) - 0.5*z;  %[nxm x 1] : univariate Gaussians
    % log-lik for the expected n_k curves of cluster k
    log_fk_Xi =  sum(reshape(log_fk_xij(:,k),m,n),1); % [n x m]:  sum over j=1,...,m: fk_Xi = prod_j sum_k pi_{jk} N(x_{ij},mu_{k},s_{k))
    log_Pik_fk_Xi(:,k) = log(pik) + log_fk_Xi;% [n x K]
    %
    log_Pik_Fik(:,k) = log_Pik_fk_Xi(:,k);
    %PikFik(:,k) = pik * exp(log_fk_Xi);
end
%Posterior = PikFik./(sum(PikFik,2)*ones(1,K));
log_Prosterior  = log_normalize(log_Pik_fk_Xi);
Posterior       = exp(log_Prosterior);
Tauik           = Posterior;



%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%                           %
% main Robust EM-MxReg loop %
%                           %
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

stored_J  = []; % to store the maximized penalized log-likelihood criterion
pen_loglik_old = -inf;
iter      = 1; % iteration number
MaxIter   = 1000;
converged = 0;
stored_K  = []; % to store the estimatde number of clusters at each iteration
while(iter<=MaxIter && ~converged)
    stored_K = [stored_K K];
    
    %     % print the value of the optimized criterion
    %     %pen_loglik = sum(log(sum(PikFik,2)),1 ) + Beta*n*sum(Alphak.*log(Alphak));
    %     %pen_loglik = (sum(log_Prosterior(:) .* Posterior(:)) - sum(log_Prosterior(:) .* log_Pik_Fik(:)))+ Beta*n*sum(Alphak.*log(Alphak));
    pen_loglik = sum(logsumexp(log_Pik_Fik,2),1) + Beta*n*sum(Alphak.*log(Alphak));
    fprintf(1,'EM Iteration : %d  | number of clusters K : %d | penalized loglikelihood: %f \n',iter-1, K, pen_loglik);
    
    
    %%%%%%%%%%%%%%%%%%%%%%%%%%%%%
    %                           %
    %       M-Step              %
    %                           %
    %%%%%%%%%%%%%%%%%%%%%%%%%%%%%
    for k=1:K
        tauik = Tauik(:,k);
        % ------Step 4 (25) ----------%
        % update of the regression coefficients
        temp =  repmat(tauik,1,m);% [m x n]
        Wk = reshape(temp',[],1);%cluster_weights(:)% [mn x 1]
        % meme chose
        % temp =  repmat(tauik,1,m)';% [m x n]
        % cluster_weights = cluster_weights(:);
        wYk = sqrt(Wk).*Ytild; % fuzzy cluster k
        wXk = sqrt(Wk*ones(1,dimBeta)).*Xstack;%[(n*m)*(M+nknots)]
        % maximization w.r.t betak: Weighted least squares
        %betak  = inv(phik'*phik + 1e-4*eye(dimBeta))*phik'*Yk;
        betak  = (wXk'*wXk + 1e-4*eye(dimBeta))\(wXk'*wYk);
        Betak(:,k) = betak;
        
        % ------ Cooected with step 5 (13) ----------%
        % mixing proportions : alphak_EM
        pik = sum(tauik)/n;%alpha_k^EM
        Pik(k) = pik;
    end
    % ------- step 5 (13) ------- %
    AlphakOld = Alphak;
    
    Alphak = Pik + Beta * Alphak.*(log(Alphak)-sum(Alphak .* log(Alphak)));
    
    % ------- step 6 (24)  ------- %
    % update beta
    E = sum(sum(AlphakOld .* log(AlphakOld)));
    eta = min ( 1 , 0.5^floor((m/2) - 1) );
    pik_max = max(Pik); alphak_max = max(AlphakOld);
    Beta = min( sum( exp(-eta*n * abs(Alphak - AlphakOld) ) )/K  , (1 - pik_max) / (-alphak_max * E ) );
    
    % ------- step 7 --------- %
    %Kold = K;
    %update the number of clusters K
    small_klas = find(Alphak < 1/n);
    % ------- step 7  (14) ------- %
    K = K - length(small_klas);
    
    % discard the small clusters
    Pik(small_klas)              = [];
    Alphak(small_klas)           = [];
    log_fk_xij(:, small_klas)    = [];
    log_Pik_fk_Xi(:, small_klas) = [];
    log_Pik_Fik(:,small_klas)    = [];
    PikFik(:,small_klas)         = [];
    log_Prosterior(:, small_klas)= [];
    Posterior(:,small_klas)      = [];
    Sigmak2(small_klas)          = [];
    Betak(:,small_klas)          = [];
    % ------- step 7  (15) normalize the Pik and Alphak ------- %
    Pik     = Pik / sum(Pik);
    Alphak  = Alphak / sum(Alphak);
    % ------- step 7 (16)  normalize the posterior prob ------- %
    Posterior = Posterior./(sum(Posterior,2)*ones(1,K));
    Tauik = Posterior;
    
    % -------- step 7 ------------ %
    % test if the partition is stable (K not changing)
    nit = 60;
    if (iter >= nit) && (stored_K(iter-(nit-1)) - K == 0); Beta = 0;  end
    % -----------step 8 (26) and (28) ---------------- %
    %%%%%%%%%%%%%%%%%%%%%%%%%%%%%
    %                           %
    %       M-Step              %
    %                           %
    %%%%%%%%%%%%%%%%%%%%%%%%%%%%%
    for k=1:K
        tauik = Tauik(:,k);
        
        temp =  repmat(tauik,1,m);
        Wk = reshape(temp',[],1);
        wYk = sqrt(Wk).*Ytild;
        wXk = sqrt(Wk*ones(1,dimBeta)).*Xstack;
        
        betak = Betak(:,k);
        
        % ----------- (26) ---------------- %
        % update the variance
        sigmak2 = sum((wYk - wXk*betak).^2)/sum(Wk);
        % -----------(28) ---------------- %
        sigmak2 = (1-gama)*sigmak2 + gama*Q;
        %
        Sigmak2(k) = sigmak2;
    end
    
    % -----------step 9 (4) ---------------- %
    %%%%%%%%%%%%%%%%%%%%%%%%%%%%%
    %                           %
    %       E-Step              %
    %                           %
    %%%%%%%%%%%%%%%%%%%%%%%%%%%%%
    for k=1:K
        alphak = Alphak(k);
        betak  = Betak(:,k);
        sigmak2 = Sigmak2(k);
        
        %%%
        %fik = normpdf(X,muk,sigmak); %Gaussian density
        z=((Ytild-Xstack*betak).^2)/sigmak2;
        log_fk_xij(:,k) = - 0.5*(log(2*pi)+log(sigmak2)) - 0.5*z;  %[nxm x 1]
        % log-lik for the n_k curves of cluster k
        log_fk_Xi =  sum(reshape(log_fk_xij(:,k),m,n),1); % [n x m]:  sum over j=1,...,m: fk_Xi = prod_j sum_k pi_{jk} N(x_{ij},mu_{k},s_{k))
        log_Pik_fk_Xi(:,k) = log(alphak) + log_fk_Xi;% [nxK]
        %%%
        log_Pik_Fik(:,k) = log_Pik_fk_Xi(:,k);
        %PikFik(:,k) = pik * exp(log_fk_Xi);
    end
    % PikFik = exp(log_Pik_Fik);
    %Posterior = PikFik./(sum(PikFik,2)*ones(1,K));
    %Posterior = exp(log_normalize(log_Pik_fk_Xi));
    log_Posterior = log_normalize(log_Pik_fk_Xi);
    Posterior = exp(log_normalize(log_Posterior));
    Tauik = Posterior;
    
    %%%%%%%%%%
    % compute the value of the optimized criterion J (12) %
    %pen_loglik = sum(log(sum(PikFik,2)),1 ) + Beta*n*sum(Alphak.*log(Alphak));
    %pen_loglik = sum(logsumexp(log_Pik_Fik,2),1) + Beta*n*sum(Alphak.*log(Alphak));
    %pen_loglik = (sum(log_Prosterior(:) .* Posterior(:)) - sum(log_Prosterior(:) .* log_Pik_Fik(:)))+ Beta*n*sum(Alphak.*log(Alphak));
    stored_J = [stored_J pen_loglik];
    %     fprintf(1,'EM Iteration : %d  | number of clusters K : %d | penalized loglikelihood: %f \n',iter, K, pen_loglik);
    %%%%%%%%%
    
    % -----------step 10 (25) ---------------- %
    %%%%%%%%%%%%%%%%%%%%%%%%%%%%%
    %                           %
    %       M-Step              %
    %                           %
    %%%%%%%%%%%%%%%%%%%%%%%%%%%%%
    BetakOld = Betak;
    for k=1:K
        tauik =Tauik(:,k);
        %pik(k) = sum(tauik)/n;
        %%%
        % update of the regression coefficients
        temp =  repmat(tauik,1,m);
        Wk = reshape(temp',[],1); %cluster_weights
        wYk = sqrt(Wk).*Ytild;
        wXk = sqrt(Wk*ones(1,dimBeta)).*Xstack;
        % maximization w.r.t betak: Weighted least squares
        %betak  = inv(phik'*phik + 0.0001*eye(dimBeta))*phik'*Yk;
        betak  = (wXk'*wXk)\(wXk'*wYk);
        %%%
        Betak(:,k) = betak;
    end
    % -----------step 11 ---------------- %
    % test of convergence
    
    distBetak = sqrt(sum((Betak - BetakOld).^2, 2));
    if (max(distBetak) < Epsilon || abs((pen_loglik - pen_loglik_old)/pen_loglik_old)<Epsilon);
        converged = 1;
    end
    pen_loglik_old = pen_loglik;
    
    iter=iter+1;
    
end% en of the Robust EM loop

[~, klas] = max (Posterior,[],2);

gmm_density   = sum(PikFik,2);
params.Pik    = Pik;
params.Alphak = Alphak;
params.Betak  = Betak;
params.Muk    = X*Betak;
params.Sigmak2 = Sigmak2;
end



