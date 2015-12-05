Shader "Custom/POM" {
	Properties {
		_MainTex ("Albedo (RGB)", 2D) = "white" {}
		_BumpMap ("Bump Map", 2D) = "white" {}
		_HeightMap ("Height Map", 2D) = "white" {}
		_HeightMapScale("Parallax Scale", Range(0.0, 0.1)) = 0.05
		_MinParallaxSamples("Min Parallax Samples", Range(0, 49)) = 25
		_MaxParallaxSamples("Max Parallax Samples", Range(50, 100)) = 75
		[MaterialToggle]_Grid("Draw Grid Lines", Float) = 0.0
		[MaterialToggle]_UVs("Draw UV Coords", Float) = 0.0
		[MaterialToggle]_SelfOcclusion("SelfOcclusion", Float) = 0.0
		_SelfOcclusionOffset("SelfOcclusion Offset", Float) = 0.01
		_SelfOcclusionStrength("SelfOcclusion Strength", Range(0,1)) = 0.6

	}
	SubShader {
		Tags{
		"RenderType" = "Opaque"
		}
		LOD 200

		Pass{
			Tags{
				"LightMode" = "ForwardBase"
			}
			CGPROGRAM

			#pragma vertex vert
			#pragma fragment frag
			#pragma target 4.0

			#include "UnityCG.cginc"

			sampler2D _MainTex;
			sampler2D _BumpMap;
			sampler2D _HeightMap;
			float4 _MainTex_ST;
			float4 _BumpMap_ST;
			float4 _HeightMap_ST;
			float _HeightMapScale;
			uint _MinParallaxSamples;
			uint _MaxParallaxSamples;
			float _Grid;
			float _UVs;
			float _SelfOcclusion;
			float _SelfOcclusionOffset;
			float _SelfOcclusionStrength;
			
			float4 _LightColor0;
			
			struct a2v {
				float4 vertex : POSITION;
				float3 normal : NORMAL;
				float4 tangent : TANGENT;
				float3 binormal : COLOR;
				float2 texcoord : TEXCOORD0;
			};
			
			struct v2f {
				float4 vertex : SV_POSITION;
				float3 normal : NORMAL;
				float2 texcoord0 : TEXCOORD0;
				float2 texcoord1 : TEXCOORD1;
				float2 texcoord2 : TEXCOORD2;
				float3 eye : COLOR0;
				float3 light : COLOR1;
			};

			v2f vert(a2v IN){
				v2f OUT;

				float3 P = mul(_Object2World, IN.vertex).xyz;
				float3 N = normalize(UnityObjectToWorldNormal(IN.normal));
				float3 E = -normalize(UnityWorldSpaceViewDir(P));
				float3 L = normalize(UnityWorldSpaceLightDir(P));

				IN.binormal = cross(normalize(IN.normal), normalize(IN.tangent.xyz)) * IN.tangent.w;

				float3x3 tangentToWorldSpace;
				tangentToWorldSpace[0] = UnityObjectToWorldNormal(normalize(IN.tangent));
				tangentToWorldSpace[1] = UnityObjectToWorldNormal(IN.binormal);
				tangentToWorldSpace[2] = UnityObjectToWorldNormal(normalize(IN.normal));
				float3x3 worldToTangentSpace = transpose(tangentToWorldSpace);

				OUT.vertex = mul(UNITY_MATRIX_MVP, IN.vertex);
				OUT.texcoord0 = TRANSFORM_TEX(IN.texcoord, _MainTex);
				OUT.texcoord1 = TRANSFORM_TEX(IN.texcoord, _BumpMap);
				OUT.texcoord2 = TRANSFORM_TEX(IN.texcoord, _HeightMap);

				OUT.eye = mul(E, worldToTangentSpace);
				OUT.normal = mul(N, worldToTangentSpace);
				OUT.light = mul(L, worldToTangentSpace);
				return OUT;
			}
			
			float4 frag(v2f IN) : SV_Target{
				float4 OUT;

				float fParallaxLimit = -length(IN.eye.xy) / IN.eye.z;
				fParallaxLimit *= _HeightMapScale;

				float2 vOffsetDir = normalize(IN.eye.xy);
				float2 vMaxOffset = vOffsetDir * fParallaxLimit;

				float3 N = normalize(IN.normal);
				float3 E = normalize(IN.eye);
				float3 L = normalize(IN.light);

				int nNumSamples = (int)lerp(_MaxParallaxSamples, _MinParallaxSamples, dot(E, N));
				float fStepSize = 1.0 / (float)nNumSamples;

				float2 dx = ddx(IN.texcoord2);
				float2 dy = ddy(IN.texcoord2);

				float fCurrRayHeight = 1.0;
				float2 vCurrOffset = float2(0, 0);
				float2 vLastOffset = float2(0, 0);

				float fLastSampledHeight = 1;
				float fCurrSampledHeight = 1;

				int nCurrSample = 0;

				while (nCurrSample < nNumSamples)
				{
					fCurrSampledHeight = tex2Dgrad(_HeightMap, IN.texcoord2 + vCurrOffset, dx, dy).x;
					if (fCurrSampledHeight > fCurrRayHeight)
					{
						float delta1 = fCurrSampledHeight - fCurrRayHeight;
						float delta2 = (fCurrRayHeight + fStepSize) - fLastSampledHeight;
						float ratio = delta1 / (delta1 + delta2);

						vCurrOffset = lerp(vCurrOffset, vLastOffset, ratio);

						fLastSampledHeight = lerp(fCurrSampledHeight, fLastSampledHeight, ratio);

						nCurrSample = nNumSamples + 1;
					}
					else
					{
						nCurrSample++;

						fCurrRayHeight -= fStepSize;

						vLastOffset = vCurrOffset;
						vCurrOffset += fStepSize * vMaxOffset;

						fLastSampledHeight = fCurrSampledHeight;
					}
				}

				float3 vFinalNormal = UnpackNormal(tex2D(_BumpMap, IN.texcoord1 + vCurrOffset)); //.a;

				float4 vFinalColor = tex2D(_MainTex, IN.texcoord0 + vCurrOffset);

				//Self-Shadowing

				float fOcclusionLimit = -length(IN.light.xy) / IN.light.z;
				fOcclusionLimit *= _HeightMapScale;

				float2 vOcclusionOffsetDir = normalize(IN.light.xy);
				float2 vMaxOcclusionOffset = vOcclusionOffsetDir * fOcclusionLimit;

				int nNumSamplesOcclusion = (int)lerp(_MaxParallaxSamples, _MinParallaxSamples, dot(L, N));
				float fStepSizeOcclusion = (1.0 - fLastSampledHeight) / (float)nNumSamplesOcclusion;

				float fCurrRayHeightOcclusion = fLastSampledHeight + _SelfOcclusionOffset;
				float2 vCurrOffsetOcclusion = vCurrOffset;
				float2 vLastOffsetOcclusion = vCurrOffset;

				float fLastSampledHeightOcclusion = fLastSampledHeight + _SelfOcclusionOffset;
				float fCurrSampledHeightOcclusion = fLastSampledHeight + _SelfOcclusionOffset;
				
				int nCurrSampleOcclusion = 0;
				float lit = 1.0;

				while (nCurrSampleOcclusion < nNumSamplesOcclusion)
				{
					fCurrSampledHeightOcclusion = tex2Dgrad(_HeightMap, IN.texcoord2 + vCurrOffsetOcclusion, dx, dy).x;
					if (fCurrSampledHeightOcclusion > fCurrRayHeightOcclusion)
					{
						if(_SelfOcclusion) lit = 1.0 - _SelfOcclusionStrength;;

						nCurrSampleOcclusion = nNumSamplesOcclusion + 1;
					}
					else
					{
						nCurrSampleOcclusion++;

						fCurrRayHeightOcclusion += fStepSize;

						vLastOffsetOcclusion = vCurrOffsetOcclusion;
						vCurrOffsetOcclusion -= fStepSizeOcclusion * vMaxOcclusionOffset;

						fLastSampledHeightOcclusion = fCurrSampledHeightOcclusion;
					}
				}


				float3 vDiffuse = _LightColor0.rgb * max(0.0f, dot(L, vFinalNormal)) * lit;

				OUT = vFinalColor * float4(vDiffuse, 1.0);

				float2 vGridCoords = frac((IN.texcoord0 + vCurrOffset) * 10.0f);

				if (_Grid && ((vGridCoords.x < 0.025f) || (vGridCoords.x > 0.975f)))
					OUT = float4(1.0f, 1.0f, 1.0f, 1.0f);

				if (_Grid && ((vGridCoords.y < 0.025f) || (vGridCoords.y > 0.975f)))
					OUT = float4(1.0f, 1.0f, 1.0f, 1.0f);

				if (_UVs) return float4(IN.texcoord2 + vCurrOffset, 0.0, 1.0);

				return OUT;
			}

			ENDCG
		}
	} 
	FallBack "Diffuse"
}