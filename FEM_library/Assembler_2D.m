function [A, F, M] = Assembler_2D(MESH, DATA, FE_SPACE, OPERATOR, TC_d, TC_t, subdomain, t)
%ASSEMBLER_2D assembler for 2D ADR equations with numerical
%quadratures.
%
%   [A, F] = ASSEMBLER_2D(MESH, DATA, FE_SPACE) given MESH and 
%   FE_SPACE structs, assemble the stiffness matrix A and rhs vector F
%   of the advection-diffusion-reaction differential operator using the
%   parameters specified in the DATA struct. The resulting matrix and
%   vector doesn't take into account for Boundary Conditions.
%
%   [A, F, M] = ASSEMBLER_2D(MESH, DATA, FE_SPACE, T) as before, but also
%   returns the mass matrix M. Moreover, the problem's parameters are
%   evaluated with respect to a given time T.
%
%   [A] = Assembler_2D(MESH, DATA, FE_SPACE, 'diffusion', [i j], [], k);
%   returns the matrix corresponding to the (i,j)-th second derivative
%   (diffusion operator) assembled over the subdomain \Omega_k
%   A spatial dependent coefficient has to be defined in DATA.diffusion
%
%   [A] = Assembler_2D(MESH, DATA, FE_SPACE, 'transport', [], [i], k);
%   returns the matrix corresponding to the (i)-th first derivative 
%   (advection operator) assembled over the subdomain \Omega_k
%   A spatial dependent coefficient has to be defined in DATA.transport{i}

%   This file is part of redbKIT.
%   Copyright (c) 2015, Ecole Polytechnique Federale de Lausanne (EPFL)
%   Author: Federico Negri <federico.negri@epfl.ch> 

if nargin < 4 || isempty(OPERATOR)
    OPERATOR = 'all';
end

if nargin < 5 || isempty(TC_d)
    TC_d = [10 10];% diagonal components of the diffusion operator by default
end

if nargin < 6 || isempty(TC_t)
    TC_t = 10; % all components of the transport operator by default
end

if nargin < 7
    subdomain = [];
end

if nargin < 8
    t = [];
end

if ~isempty(subdomain)    
    index_subd = [];
    for q = 1 : length(subdomain)
        index_subd = [index_subd find(MESH.elements(FE_SPACE.numElemDof+1,:) == subdomain(q))];
    end
    MESH.elements = MESH.elements(:,index_subd);
    MESH.numElem  = size(MESH.elements,2);
else
    index_subd = [1:MESH.numElem];
end


%% Computations of all quadrature nodes in the elements
x = zeros(MESH.numElem,FE_SPACE.numQuadNodes); y = x;
coord_ref = MESH.chi;

for j = 1 : 3
      i = MESH.elements(j,:);
      vtemp = MESH.vertices(1,i);
      x = x + vtemp'*coord_ref(j,:);
      vtemp = MESH.vertices(2,i);
      y = y + vtemp'*coord_ref(j,:);
end


%% Evaluation of coefficients in the quadrature nodes
mu  = DATA.diffusion(x,y,t,DATA.param);
si  = DATA.reaction(x,y,t,DATA.param);

switch class(DATA.force)
      case {'function_handle','inline'}
            f  = DATA.force(x,y,t,DATA.param);
            
      case 'double'
            if size(DATA.force,1)>1 && size(DATA.force,2)>1
                  f = DATA.force(index_subd,:);
                  
            elseif length(DATA.force)==MESH.numNodes
                  
                  f = zeros(MESH.numElem,FE_SPACE.numQuadNodes);
                  for j = 1 : FE_SPACE.numElemDof
                        i = MESH.elements(j,:);
                        f = f + DATA.force(i)*FE_SPACE.phi(j,:);
                  end
            end
end

bx  = DATA.transport{1}(x,y,t,DATA.param);
by  = DATA.transport{2}(x,y,t,DATA.param);

one = ones(MESH.numElem,FE_SPACE.numQuadNodes);

mu  = mu.*one;
bx  = bx.*one;
by  = by.*one;
si  = si.*one;
f   = f.*one;


%% Vectorized assemly, returns matrices in sparse vector format
[Arows, Acols, Acoef, Mcoef, Rrows, Rcoef] = ADR_mex_assembler(OPERATOR, TC_d, TC_t, MESH.elements, FE_SPACE.numElemDof, mu, bx, by, si, f,...
                      FE_SPACE.quad_weights,MESH.invjac(index_subd,1,1)',MESH.invjac(index_subd,2,1)',MESH.invjac(index_subd,1,2)',MESH.invjac(index_subd,2,2)',...
                      FE_SPACE.phi,FE_SPACE.dcsiphi,FE_SPACE.detaphi, MESH.jac(index_subd));


%% Build sparse matrices and rhs
A    = sparse(Arows,Acols,Acoef,MESH.numNodes,MESH.numNodes);
M    = sparse(Arows,Acols,Mcoef,MESH.numNodes,MESH.numNodes);
F    = sparse(Rrows,1,Rcoef,MESH.numNodes,1);

return