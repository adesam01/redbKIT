%CSM_ASSEMBLER assembler class for 2D/3D Computational Solid Mechanics
% CSM_ASSEMBLER methods:
%    CSM_Assembler                - constructor
%    SetMaterialParameters        - set parameters vector
%    compute_volumetric_forces    - assemble volumetric rhs contribute 
%    compute_surface_forces       - assemble surface rhs contribute 
%    compute_external_forces      - assemble all external forces
%    compute_mass                 - assemble mass matrix
%    compute_stress               - compute stress for postprocessing
%    compute_internal_forces      - assemble vector of internal forces
%    compute_jacobian             - assemble jacobian (tangent stiffness) matrix
%
% CSM_ASSEMBLER properties:
%    M_MESH             - struct containing MESH data
%    M_DATA             - struct containing DATA information
%    M_FE_SPACE         - struct containing Finite Element space data
%    M_MaterialModel    - string containing name of the material model
%    M_MaterialParam    - vector containing material parameters

%   This file is part of redbKIT.
%   Copyright (c) 2016, Ecole Polytechnique Federale de Lausanne (EPFL)
%   Author: Federico Negri <federico.negri@epfl.ch>

classdef CSM_Assembler < handle
    
    properties (GetAccess = public, SetAccess = protected)
        M_MESH;
        M_DATA;
        M_FE_SPACE;
        M_subdomain;
        M_MaterialModel;
        M_MaterialParam;
    end
   
    methods
        
        %==========================================================================
        %% Constructor
        function obj = CSM_Assembler( MESH, DATA, FE_SPACE )
            
            obj.M_MESH      = MESH;
            obj.M_DATA      = DATA;
            obj.M_FE_SPACE  = FE_SPACE;
            obj.M_MaterialModel = DATA.Material_Model;
            obj = SetMaterialParameters(obj);
            
        end
        
        %==========================================================================
        %% SetMaterialParameters
        function obj = SetMaterialParameters( obj )
            
            switch obj.M_MaterialModel
                case 'Linear'
                    obj.M_MaterialParam = [obj.M_DATA.Young obj.M_DATA.Poisson];
                    
                case 'StVenantKirchhoff'
                    obj.M_MaterialParam = [obj.M_DATA.Young obj.M_DATA.Poisson];
                    
                case {'NeoHookean','NeoHookean2'}
                    obj.M_MaterialParam = [obj.M_DATA.Young obj.M_DATA.Poisson];%[DATA.Shear DATA.Poisson];
                
                case {'RaghavanVorp',}
                    obj.M_MaterialParam = [obj.M_DATA.Alpha obj.M_DATA.Beta obj.M_DATA.Bulk];
                     
                case 'SEMMT'
                    obj.M_MaterialParam = [obj.M_DATA.Young obj.M_DATA.Poisson obj.M_DATA.Stiffening_power];
            end
            
        end
        
        %==========================================================================
        %% Compute Volumetric Forces
        function F_ext = compute_volumetric_forces( obj, t )
            
            if nargin < 2 || isempty(t)
                t = [];
            end
            
            % Computations of all quadrature nodes in the elements
            coord_ref = obj.M_MESH.chi;
            switch obj.M_MESH.dim
                
                case 2
                    
                    x = zeros(obj.M_MESH.numElem,obj.M_FE_SPACE.numQuadNodes); y = x;
                    for j = 1 : 3
                        i = obj.M_MESH.elements(j,:);
                        vtemp = obj.M_MESH.vertices(1,i);
                        x = x + vtemp'*coord_ref(j,:);
                        vtemp = obj.M_MESH.vertices(2,i);
                        y = y + vtemp'*coord_ref(j,:);
                    end
                    
                    % Evaluation of external forces in the quadrature nodes
                    for k = 1 : obj.M_MESH.dim
                        f{k}  = obj.M_DATA.force{k}(x,y,t,obj.M_DATA.param);
                    end
                    
                case 3
                    
                    x = zeros(obj.M_MESH.numElem,obj.M_FE_SPACE.numQuadNodes); y = x; z = x;
                    
                    for j = 1 : 4
                        i = obj.M_MESH.elements(j,:);
                        vtemp = obj.M_MESH.vertices(1,i);
                        x = x + vtemp'*coord_ref(j,:);
                        vtemp = obj.M_MESH.vertices(2,i);
                        y = y + vtemp'*coord_ref(j,:);
                        vtemp = obj.M_MESH.vertices(3,i);
                        z = z + vtemp'*coord_ref(j,:);
                    end
                    
                    % Evaluation of external forces in the quadrature nodes
                    for k = 1 : obj.M_MESH.dim
                        f{k}  = obj.M_DATA.force{k}(x,y,z,t,obj.M_DATA.param);
                    end
                    
            end
            % C_OMP assembly, returns matrices in sparse vector format

            F_ext = [];
            for k = 1 : obj.M_MESH.dim
                
                [rowF, coefF] = CSM_assembler_ExtForces(f{k}, obj.M_MESH.elements, obj.M_FE_SPACE.numElemDof, ...
                    obj.M_FE_SPACE.quad_weights, obj.M_MESH.jac, obj.M_FE_SPACE.phi);
                
                % Build sparse matrix and vector
                F_ext    = [F_ext; GlobalAssemble(rowF, 1, coefF, obj.M_MESH.numNodes, 1)];
                
            end
            
        end
        
        %==========================================================================
        %% Compute Surface Forces
        function F_ext = compute_surface_forces( obj, t )
            
            if nargin < 2 || isempty(t)
                t = [];
            end
            
            % To be Coded
            
        end
        
        %==========================================================================
        %% Compute External Forces
        function F_ext = compute_external_forces( obj, t )
            
            if nargin < 2 || isempty(t)
                t = [];
            end
            
            F_ext = compute_volumetric_forces( obj, t ) + compute_surface_forces( obj, t );
            
        end
        
        %==========================================================================
        %% Compute mass matrix
        function [M] = compute_mass( obj )
            
            % C_OMP assembly, returns matrices in sparse vector format
            [rowM, colM, coefM] = Mass_assembler_C_omp(obj.M_MESH.dim, obj.M_MESH.elements, obj.M_FE_SPACE.numElemDof, ...
                obj.M_FE_SPACE.quad_weights, obj.M_MESH.jac, obj.M_FE_SPACE.phi);
            
            % Build sparse matrix
            M_scalar   = GlobalAssemble(rowM, colM, coefM, obj.M_MESH.numNodes, obj.M_MESH.numNodes);
            M          = [];
            for k = 1 : obj.M_FE_SPACE.numComponents
                M = blkdiag(M, M_scalar);
            end
            
        end
        
        %==========================================================================
        %% Compute stress
        function [S] = compute_stress(obj, U_h)
            
            % C_OMP compute element stresses, returns dense matrix of size
            % N_elements x MESH.dim^2
            
            [quad_nodes, quad_weights]   = quadrature(obj.M_MESH.dim, 1);
            [phi, dphi_ref]              = fem_basis(obj.M_FE_SPACE.dim, obj.M_FE_SPACE.fem, quad_nodes);
            
            [S] = CSM_assembler_C_omp_Q2(obj.M_MESH.dim, [obj.M_MaterialModel,'_stress'], obj.M_MaterialParam, ...
                U_h, obj.M_MESH.elements, obj.M_FE_SPACE.numElemDof,...
                quad_weights, obj.M_MESH.invjac, obj.M_MESH.jac, phi, dphi_ref);
            
        end
        
        %==========================================================================
        %% Compute internal forces
        function [F_in] = compute_internal_forces(obj, U_h)
            
            % C_OMP assembly, returns matrices in sparse vector format
            [rowG, coefG] = ...
                CSM_assembler_C_omp_Q2(obj.M_MESH.dim, [obj.M_MaterialModel,'_forces'], obj.M_MaterialParam, U_h, ...
                obj.M_MESH.elements, obj.M_FE_SPACE.numElemDof, ...
                obj.M_FE_SPACE.quad_weights, obj.M_MESH.invjac, obj.M_MESH.jac, obj.M_FE_SPACE.phi, obj.M_FE_SPACE.dphi_ref);
            
            % Build sparse matrix and vector
            F_in    = GlobalAssemble(rowG, 1, coefG, obj.M_MESH.numNodes*obj.M_MESH.dim, 1);
            
        end
        
        %==========================================================================
        %% Compute internal forces Residual
        function [dF_in] = compute_jacobian(obj, U_h)

            % C_OMP assembly, returns matrices in sparse vector format
            [rowdG, coldG, coefdG] = ...
                CSM_assembler_C_omp_Q2(obj.M_MESH.dim, [obj.M_MaterialModel,'_jacobian'], obj.M_MaterialParam, U_h, ...
                obj.M_MESH.elements, obj.M_FE_SPACE.numElemDof, ...
                obj.M_FE_SPACE.quad_weights, obj.M_MESH.invjac, obj.M_MESH.jac, obj.M_FE_SPACE.phi, obj.M_FE_SPACE.dphi_ref);
            
            % Build sparse matrix and vector
            dF_in   = GlobalAssemble(rowdG, coldG, coefdG, obj.M_MESH.numNodes*obj.M_MESH.dim, obj.M_MESH.numNodes*obj.M_MESH.dim);
        end
        
    end
    
end